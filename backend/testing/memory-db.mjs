// Minimal in-memory Firestore double with optimistic-concurrency transactions.
// Enough of the API surface for this backend. Not a substitute for the
// Firestore emulator (see docs/backend.md), but it exercises retries/contention.

class Snapshot {
  constructor(ref, data, version) { this.ref = ref; this.id = ref.id; this._data = data; this.version = version; }
  get exists() { return this._data !== undefined; }
  data() { return this._data === undefined ? undefined : structuredClone(this._data); }
  get(field) { return this._data === undefined ? undefined : structuredClone(this._data[field]); }
}

class DocRef {
  constructor(db, collection, id) { this.db = db; this.collectionName = collection; this.id = id; }
  get path() { return `${this.collectionName}/${this.id}`; }
  async get() { await Promise.resolve(); return this.db._snapshot(this); }
  async set(data) { await Promise.resolve(); this.db._write(this.path, structuredClone(data)); }
  async create(data) {
    await Promise.resolve();
    if (this.db.docs.has(this.path)) throw Object.assign(new Error('ALREADY_EXISTS'), { code: 6 });
    this.db._write(this.path, structuredClone(data));
  }
  async update(data) {
    await Promise.resolve();
    if (!this.db.docs.has(this.path)) throw Object.assign(new Error('NOT_FOUND'), { code: 5 });
    this.db._write(this.path, { ...this.db.docs.get(this.path), ...structuredClone(data) });
  }
  async delete() { this.db._remove(this.path); }
}

class Collection {
  constructor(db, name) { this.db = db; this.name = name; }
  doc(id) { return new DocRef(this.db, this.name, id); }
}

/** Enforces Firestore's value rules that tests would otherwise miss. */
function assertStorable(value, path, insideArray = false) {
  if (Array.isArray(value)) {
    if (insideArray) throw new Error(`INVALID_ARGUMENT: nested arrays are not supported (${path})`);
    value.forEach((item) => assertStorable(item, path, true));
  } else if (value && typeof value === 'object' && !(value instanceof Date)) {
    for (const [key, item] of Object.entries(value)) {
      if (item === undefined) throw new Error(`INVALID_ARGUMENT: undefined at ${path}.${key}`);
      assertStorable(item, path, false);
    }
  }
}

export class MemoryFirestore {
  constructor() { this.docs = new Map(); this.versions = new Map(); this.writes = 0; this.failNext = 0; }
  collection(name) { return new Collection(this, name); }
  _snapshot(ref) {
    return new Snapshot(ref, this.docs.get(ref.path), this.versions.get(ref.path) ?? 0);
  }
  _write(path, data) {
    assertStorable(data, path);
    this.docs.set(path, data); this.versions.set(path, (this.versions.get(path) ?? 0) + 1); this.writes++; }
  _remove(path) { this.docs.delete(path); this.versions.set(path, (this.versions.get(path) ?? 0) + 1); }
  async getAll(...refs) { return Promise.all(refs.map((ref) => ref.get())); }

  async runTransaction(fn, { attempts = 8 } = {}) {
    for (let attempt = 0; attempt < attempts; attempt++) {
      const reads = new Map();
      const staged = [];
      let wrote = false;
      const tx = {
        get: async (ref) => {
          if (wrote) throw new Error('Firestore transactions require all reads before writes');
          await Promise.resolve();
          const snap = this._snapshot(ref);
          reads.set(ref.path, snap.version);
          return snap;
        },
        getAll: async (...refs) => Promise.all(refs.map((ref) => tx.get(ref))),
        set: (ref, data) => { wrote = true; staged.push(['set', ref, data]); return tx; },
        create: (ref, data) => { wrote = true; staged.push(['create', ref, data]); return tx; },
        update: (ref, data) => { wrote = true; staged.push(['update', ref, data]); return tx; },
        delete: (ref) => { wrote = true; staged.push(['delete', ref]); return tx; },
      };
      const result = await fn(tx);
      if (this.failNext > 0) { this.failNext--; throw new Error('UNAVAILABLE'); }
      let conflict = false;
      for (const [path, version] of reads) if ((this.versions.get(path) ?? 0) !== version) conflict = true;
      if (conflict) { await new Promise((resolve) => setImmediate(resolve)); continue; }
      for (const [kind, ref, data] of staged) {
        if (kind === 'create') {
          if (this.docs.has(ref.path)) throw Object.assign(new Error('ALREADY_EXISTS'), { code: 6 });
          this._write(ref.path, structuredClone(data));
        } else if (kind === 'set') this._write(ref.path, structuredClone(data));
        else if (kind === 'update') this._write(ref.path, { ...(this.docs.get(ref.path) ?? {}), ...structuredClone(data) });
        else this._remove(ref.path);
      }
      return result;
    }
    throw new Error('ABORTED: too much contention');
  }
}
