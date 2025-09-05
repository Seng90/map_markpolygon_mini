// server.js
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
require('dotenv').config();

const fs = require('fs');
const path = require('path');
const turf = require('@turf/turf'); // Node v18+ มี fetch มาในตัวแล้ว

const app = express();
app.use(cors());
app.use(express.json({ limit: '5mb' }));

// ===== DB =====
const pool = new Pool({
  host: process.env.PGHOST,
  port: process.env.PGPORT,
  database: process.env.PGDATABASE,
  user: process.env.PGUSER,
  password: process.env.PGPASSWORD,
  ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : false,
});

// ปรับ points ให้เป็นอาร์เรย์เสมอก่อนส่งออก
function normalizeRowPoints(row) {
  if (!row) return row;
  try {
    if (typeof row.points === 'string') {
      row.points = JSON.parse(row.points);
    }
  } catch (_) { }
  return row;
}

// ===== Health =====
app.get('/health', (_req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});
app.get('/db/ping', async (_req, res) => {
  try {
    const r = await pool.query('SELECT NOW() as now');
    res.json({ ok: true, now: r.rows[0].now });
  } catch (e) {
    console.error('DB PING ERROR:', e);
    res.status(500).json({ ok: false, error: String(e) });
  }
});

// ===== CRUD polygons =====
// CREATE
app.post('/polygons', async (req, res) => {
  try {
    const { name, points, area_sq_m } = req.body;
    if (!name || !Array.isArray(points) || points.length < 3) {
      return res.status(400).json({ error: 'Invalid payload: name & points[>=3] required' });
    }
    const q = `INSERT INTO public.polygons (name, points, area_sq_m)
               VALUES ($1, $2, $3)
               RETURNING *`;
    const r = await pool.query(q, [name, JSON.stringify(points), area_sq_m ?? null]);
    res.json(normalizeRowPoints(r.rows[0]));
  } catch (e) {
    console.error('POST /polygons ERROR:', e);
    res.status(500).json({ error: 'Server error', detail: String(e) });
  }
});
// READ
app.get('/polygons', async (_req, res) => {
  try {
    const r = await pool.query('SELECT * FROM public.polygons ORDER BY id DESC');
    res.json(r.rows.map(normalizeRowPoints));
  } catch (e) {
    console.error('GET /polygons ERROR:', e);
    res.status(500).json({ error: 'Server error', detail: String(e) });
  }
});
// DELETE
app.delete('/polygons/:id', async (req, res) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'invalid id' });
    await pool.query('DELETE FROM public.polygons WHERE id = $1', [id]);
    res.json({ ok: true });
  } catch (e) {
    console.error('DELETE /polygons/:id ERROR:', e);
    res.status(500).json({ error: 'Server error', detail: String(e) });
  }
});
// UPDATE
app.put('/polygons/:id', async (req, res) => {
  try {
    const id = Number(req.params.id);
    const { name, points, area_sq_m } = req.body;
    if (!Number.isInteger(id)) return res.status(400).json({ error: 'invalid id' });
    if (!name || !Array.isArray(points) || points.length < 3) {
      return res.status(400).json({ error: 'Invalid payload: name & points[>=3] required' });
    }
    const q = `UPDATE public.polygons
               SET name = $1, points = $2, area_sq_m = $3
               WHERE id = $4
               RETURNING *`;
    const r = await pool.query(q, [name, JSON.stringify(points), area_sq_m ?? null, id]);
    if (r.rows.length === 0) return res.status(404).json({ error: 'Not found' });
    res.json(normalizeRowPoints(r.rows[0]));
  } catch (e) {
    console.error('PUT /polygons/:id ERROR:', e);
    res.status(500).json({ error: 'Server error', detail: String(e) });
  }
});

// ===== Helpers สำหรับวิเคราะห์พื้นที่ =====
function polygonBbox(points) {
  let minLat = 90, minLng = 180, maxLat = -90, maxLng = -180;
  for (const { lat, lng } of points) {
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
  }
  const pad = 0.01;
  return [minLat - pad, minLng - pad, maxLat + pad, maxLng + pad];
}
function adminLevelLabel(level) {
  const l = parseInt(level, 10);
  if (Number.isNaN(l)) return 'Administrative';
  if (l <= 4) return 'Region/Province';
  if (l === 5 || l === 6) return 'District';
  if (l === 7 || l === 8) return 'City/Town';
  if (l >= 9) return 'Village/Subdistrict';
  return 'Administrative';
}
function propNameFlexible(props = {}) {
  if (!props || typeof props !== 'object') return '(ไม่มีชื่อ)';

  // 1) ลองคีย์ยอดฮิตก่อน (เร็วและแม่นในหลายชุดข้อมูล)
  const preferred = [
    'name', 'NAME', 'NAME_EN', 'NAME_ENG', 'NAME_LOCAL',
    'NAME_1', 'NAME_2', 'NAME_3', 'NAME_4',
    'NL_NAME_1', 'NL_NAME_2', 'NL_NAME_3', 'NL_NAME_4',
    'shapeName', 'shapeName_en', 'shapeName_local',
    'ADM1_EN', 'ADM2_EN', 'ADM3_EN', 'ADM4_EN',
    'ADM1_LC', 'ADM2_LC', 'ADM3_LC', 'ADM4_LC',
    'PROV_NAME', 'DIST_NAME', 'TAM_NAME', 'VIL_NAME'
  ];
  for (const k of preferred) {
    if (k in props) {
      const v = String(props[k] ?? '').trim();
      if (v) return v;
    }
  }

  // 2) ถ้ายังไม่ได้ ให้ "สแกนทุกคีย์ที่มีคำว่า name" (case-insensitive)
  //    แล้วเลือกค่าตัวแรกที่ไม่ว่าง
  for (const [k, v] of Object.entries(props)) {
    if (/name/i.test(k)) {
      const s = String(v ?? '').trim();
      if (s) return s;
    }
  }

  // 3) fallback: แสดง code เพื่อช่วยตามรอย
  const codeKeys = ['GID_0', 'GID_1', 'GID_2', 'GID_3', 'GID_4', 'HASC_1', 'HASC_2', 'shapeID', 'shapeGroup'];
  for (const k of codeKeys) {
    if (k in props) return `(ไม่มีชื่อ: ${k}=${props[k]})`;
  }
  return '(ไม่มีชื่อ)';
}


function labelFromADM(level) {
  if (level === 1) return 'Province';
  if (level === 2) return 'District';
  return 'Administrative';
}

// ===== Local Laos dataset (แนะนำให้ใช้เสมอในลาว) =====
let LAO_ADM1 = null; // provinces
let LAO_ADM2 = null; // districts
function loadLaoDatasetsOnce() {
  if (!LAO_ADM1) {
    const p1 = path.join(__dirname, 'data', 'lao_adm1.geojson');
    if (fs.existsSync(p1)) {
      LAO_ADM1 = JSON.parse(fs.readFileSync(p1, 'utf8'));
      console.log('[LAO_ADM1] loaded features:', LAO_ADM1.features?.length ?? 0);
    } else {
      console.warn('[lao_adm1.geojson] not found in backend/data');
    }
  }
  if (!LAO_ADM2) {
    const p2 = path.join(__dirname, 'data', 'lao_adm2.geojson');
    if (fs.existsSync(p2)) {
      LAO_ADM2 = JSON.parse(fs.readFileSync(p2, 'utf8'));
      console.log('[LAO_ADM2] loaded features:', LAO_ADM2.features?.length ?? 0);
    } else {
      console.warn('[lao_adm2.geojson] not found in backend/data');
    }
  }
}

// POST /analyze-overlap-local-lao
app.post('/analyze-overlap-local-lao', async (req, res) => {
  try {
    const { points, unit, levels } = req.body; // unit: 'm2'|'km2', levels: [1,2]
    if (!Array.isArray(points) || points.length < 3) {
      return res.status(400).json({ error: 'Invalid polygon points' });
    }
    loadLaoDatasetsOnce();
    if (!LAO_ADM1 && !LAO_ADM2) {
      return res.status(500).json({
        error: 'Laos datasets not found. Put lao_adm1.geojson & lao_adm2.geojson in backend/data.',
      });
    }

    // 1) ผู้ใช้ → Polygon (lon,lat) และทำความสะอาด
    const ring = points.map((p) => [p.lng, p.lat]);
    ring.push(ring[0]);
    let userPoly = turf.polygon([ring], { name: 'user_polygon' });
    try { userPoly = turf.cleanCoords(userPoly); } catch { }
    try { userPoly = turf.buffer(userPoly, 0, { units: 'meters' }); } catch { }

    // 2) เลือกชุดข้อมูล
    const selLevels = Array.isArray(levels) && levels.length > 0 ? levels : [1, 2];
    const datasets = [];
    if (selLevels.includes(1) && LAO_ADM1) datasets.push({ level: 1, fc: LAO_ADM1 });
    if (selLevels.includes(2) && LAO_ADM2) datasets.push({ level: 2, fc: LAO_ADM2 });

    // 3) ช่วยตัดเร็วด้วย bbox intersect (ไม่ใช่ booleanIntersects)
    const userBbox = turf.bbox(userPoly);
    function bboxOverlap(b1, b2) {
      const [minX1, minY1, maxX1, maxY1] = b1;
      const [minX2, minY2, maxX2, maxY2] = b2;
      return !(maxX1 < minX2 || maxX2 < minX1 || maxY1 < minY2 || maxY2 < minY1);
    }

    // 4) ตัวช่วย: รวมพื้นที่ซ้อนทับกับ MultiPolygon
    function overlapWithFeature(user, feature) {
      let adminArea = 0;
      let overlapArea = 0;

      const geom = feature.geometry;
      if (!geom) return { adminArea, overlapArea };

      const pushPart = (coords) => {
        // สร้าง Polygon หนึ่งชิ้นจากพิกัดของ part นั้น
        let poly;
        try {
          poly = turf.polygon(coords);
          poly = turf.cleanCoords(poly);
          poly = turf.buffer(poly, 0, { units: 'meters' }); // แก้ self-intersections
        } catch {
          return;
        }
        // รวมพื้นที่เขต (รวมทุก part)
        try { adminArea += turf.area(poly); } catch { }

        // intersect พาร์ทนี้
        try {
          const inter = turf.intersect(user, poly);
          if (inter) {
            try { overlapArea += turf.area(inter); } catch { }
          }
        } catch {
          // ถ้าตัดไม่สำเร็จ แต่ศูนย์กลางผู้ใช้อยู่ในพาร์ทนี้ → ให้ถือว่าทับ (fallback เล็กน้อย)
          try {
            const c = turf.centroid(user);
            if (turf.booleanPointInPolygon(c, poly)) {
              // อย่างน้อยให้ถือว่าทับพื้นที่ของผู้ใช้ทั้งหมด (Upper bound)
              overlapArea = Math.max(overlapArea, turf.area(user));
            }
          } catch { }
        }
      };

      if (geom.type === 'Polygon') {
        pushPart(geom.coordinates);
      } else if (geom.type === 'MultiPolygon') {
        for (const part of geom.coordinates) {
          pushPart(part);
        }
      } else {
        // geometry แบบอื่น (น้อยมาก) ข้ามไป
      }
      return { adminArea, overlapArea };
    }

    const toUnit = unit === 'km2' ? (v) => v / 1_000_000 : (v) => v;
    const areaUnitLabel = unit === 'km2' ? 'km²' : 'm²';
    const results = [];

    // 5) loop ฟีเจอร์ทั้งหมด
    for (const ds of datasets) {
      const feats = ds.fc.features || [];
      for (const f of feats) {
        // skip ถ้า bbox ไม่ซ้อน
        const fb = turf.bbox(f);
        if (!bboxOverlap(userBbox, fb)) continue;

        const { adminArea, overlapArea } = overlapWithFeature(userPoly, f);
        if (adminArea <= 0 || overlapArea <= 0) continue;

        const candidateName = propNameFlexible(f.properties);
        if (!candidateName || candidateName === '(ไม่มีชื่อ)') {
          const sampleKeys = Object.keys(f.properties || {}).slice(0, 10).join(', ');
          console.warn('NO_NAME_FEATURE',
            { level: ds.level, keys: sampleKeys, id: f.id ?? null }
          );
        }

        results.push({
          id: f.id ?? null,
          name: propNameFlexible(f.properties),
          adminLevel: `ADM${ds.level}`,
          label: labelFromADM(ds.level),
          areaOfAdmin: toUnit(adminArea),
          overlapArea: toUnit(overlapArea),
          percent: (overlapArea / adminArea) * 100,
          unit: areaUnitLabel,
        });
      }
    }

    results.sort((a, b) => b.percent - a.percent);
    return res.json({ items: results.slice(0, 50) });
  } catch (err) {
    console.error('POST /analyze-overlap-local-lao ERROR:', err);
    return res.status(500).json({ error: 'internal_error', detail: String(err) });
  }
});


// ===== Overpass (สำรอง) =====
app.post('/analyze-overlap', async (req, res) => {
  try {
    const { points, unit } = req.body;
    if (!Array.isArray(points) || points.length < 3) {
      return res.status(400).json({ error: 'Invalid polygon points' });
    }

    const ring = points.map((p) => [p.lng, p.lat]);
    ring.push(ring[0]);
    let userPoly = turf.polygon([ring], { name: 'user_polygon' });
    if (!turf.booleanValid(userPoly)) userPoly = turf.cleanCoords(userPoly);

    // ใช้ centroid -> is_in เพื่อหาเขตที่ครอบจุดนี้
    const c = turf.centroid(userPoly).geometry.coordinates; // [lon, lat]
    const cLon = c[0], cLat = c[1];

    const overpassUrl = 'https://overpass-api.de/api/interpreter';
    const query = `
      [out:json][timeout:25];
      is_in(${cLat},${cLon})->.a;
      relation(area.a)["boundary"="administrative"];
      out body tags center;
      out geom;`;

    const resp = await fetch(overpassUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8' },
      body: `data=${encodeURIComponent(query)}`,
    });
    if (!resp.ok) {
      const text = await resp.text();
      return res.status(502).json({ error: 'Overpass error', detail: text });
    }
    const data = await resp.json();

    const toUnit = unit === 'km2' ? (v) => v / 1_000_000 : (v) => v;
    const areaUnitLabel = unit === 'km2' ? 'km²' : 'm²';
    const results = [];

    for (const r of data.elements || []) {
      if (r.type !== 'relation' || !r.tags || !Array.isArray(r.geometry) || r.geometry.length < 3) continue;

      const name = r.tags.name || r.tags['name:en'] || r.tags['name:local'] || '(ไม่มีชื่อ)';
      const adminLevel = r.tags.admin_level || '';
      const label = adminLevelLabel(adminLevel);

      const coords = r.geometry.map((g) => [g.lon, g.lat]);
      if (coords.length < 3) continue;
      const first = coords[0], last = coords[coords.length - 1];
      if (first[0] !== last[0] || first[1] !== last[1]) coords.push(first);

      let adminPoly = null;
      try {
        adminPoly = turf.polygon([coords]);
        if (!turf.booleanValid(adminPoly)) {
          const hull = turf.convex(turf.featureCollection([turf.points(coords)]));
          if (hull) adminPoly = hull;
        }
      } catch {
        continue;
      }
      if (!adminPoly) continue;

      let inter = null;
      try { inter = turf.intersect(userPoly, adminPoly); } catch { }
      if (!inter) continue;

      const adminArea = turf.area(adminPoly);
      const overlapArea = turf.area(inter);
      if (overlapArea <= 0 || adminArea <= 0) continue;

      results.push({
        id: r.id,
        name,
        adminLevel,
        label,
        areaOfAdmin: toUnit(adminArea),
        overlapArea: toUnit(overlapArea),
        percent: (overlapArea / adminArea) * 100,
        unit: areaUnitLabel,
      });
    }

    results.sort((a, b) => b.percent - a.percent);
    res.json({ items: results.slice(0, 20) });
  } catch (err) {
    console.error('POST /analyze-overlap ERROR:', err);
    res.status(500).json({ error: 'internal_error', detail: String(err) });
  }
});

// ===== Start =====
const port = process.env.PORT || 3000;
app.listen(port, () => console.log(`API running at http://localhost:${port}`));

module.exports = app;
