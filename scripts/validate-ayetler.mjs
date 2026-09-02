#!/usr/bin/env node
// Validates assets/data/ayetler.json against the constraints required for the
// "Günün Âyeti" (Verse of the Day) dataset. Run with: node scripts/validate-ayetler.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA_PATH = path.resolve(__dirname, '..', 'assets', 'data', 'ayetler.json');
const MIN_RECORDS = 366;
const REQUIRED_FIELDS = ['sureAdi', 'sureNo', 'ayetNo', 'meal', 'kaynak', 'isSampleData'];

const errors = [];
const warnings = [];

function fail(msg) {
  errors.push(msg);
}

// 1. JSON parse
let raw;
let data;
try {
  raw = fs.readFileSync(DATA_PATH, 'utf8');
} catch (e) {
  console.error(`OKUNAMADI: ${DATA_PATH} — ${e.message}`);
  process.exit(1);
}
try {
  data = JSON.parse(raw);
} catch (e) {
  console.error(`JSON PARSE HATASI: ${e.message}`);
  process.exit(1);
}

const list = data.tr;
if (!Array.isArray(list)) {
  console.error('HATA: data.tr bir dizi (array) değil.');
  process.exit(1);
}

// 2. total record count
if (list.length < MIN_RECORDS) {
  fail(`Toplam kayıt sayısı ${list.length}, en az ${MIN_RECORDS} olmalı.`);
}

// 3-6. per-record checks
const seenKeys = new Set();
const duplicates = [];
let sampleDataCount = 0;

list.forEach((entry, idx) => {
  const where = `#${idx} (sureNo=${entry?.sureNo}, ayetNo=${entry?.ayetNo})`;

  for (const field of REQUIRED_FIELDS) {
    if (!(field in entry)) {
      fail(`${where}: '${field}' alanı eksik.`);
      continue;
    }
    const value = entry[field];
    if (field === 'isSampleData') {
      if (typeof value !== 'boolean') fail(`${where}: 'isSampleData' boolean değil.`);
      continue;
    }
    if (field === 'sureNo') {
      if (typeof value !== 'number' || !Number.isInteger(value)) fail(`${where}: 'sureNo' tam sayı değil.`);
      continue;
    }
    if (typeof value !== 'string' || value.trim().length === 0) {
      fail(`${where}: '${field}' boş veya string değil.`);
    }
  }

  if (typeof entry.sureNo === 'number') {
    if (entry.sureNo < 1 || entry.sureNo > 114) {
      fail(`${where}: sureNo (${entry.sureNo}) 1-114 aralığının dışında.`);
    }
  }

  if (entry.isSampleData === true) {
    sampleDataCount++;
  }

  if (typeof entry.sureNo === 'number' && typeof entry.ayetNo === 'string') {
    const key = `${entry.sureNo}:${entry.ayetNo}`;
    if (seenKeys.has(key)) {
      duplicates.push(key);
    } else {
      seenKeys.add(key);
    }
  }
});

if (duplicates.length > 0) {
  fail(`Duplicate sureNo+ayetNo kombinasyonları bulundu (${duplicates.length}): ${duplicates.slice(0, 20).join(', ')}${duplicates.length > 20 ? ', ...' : ''}`);
}

if (sampleDataCount > 0) {
  fail(`${sampleDataCount} kayıt hâlâ isSampleData=true.`);
}

// Report
console.log('--- Günün Âyeti Veri Seti Doğrulama Raporu ---');
console.log(`Toplam kayıt: ${list.length}`);
console.log(`Farklı sûre sayısı: ${new Set(list.map(e => e.sureNo)).size}`);
console.log(`Duplicate sayısı: ${duplicates.length}`);
console.log(`isSampleData=true kayıt sayısı: ${sampleDataCount}`);

if (warnings.length > 0) {
  console.log(`\nUyarılar (${warnings.length}):`);
  warnings.forEach(w => console.log(`  - ${w}`));
}

if (errors.length > 0) {
  console.log(`\nHATALAR (${errors.length}):`);
  errors.forEach(e => console.log(`  - ${e}`));
  console.log('\nSONUÇ: BAŞARISIZ');
  process.exit(1);
}

console.log('\nSONUÇ: BAŞARILI — tüm kontroller geçti.');
