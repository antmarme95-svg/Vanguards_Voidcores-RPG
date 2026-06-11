// Global pub/sub. Engine-agnostic — maps to an autoload with signals in Godot.
// Channels used across the game:
//   creation:complete   { save }
//   contract:signed     { origin }
//   scene:transition    { to }
//   quest:update        { quest }
//   quest:toast         { text }
//   combat:enemyDown    { remaining }
//   combat:playerHit    { amount }
//   core:destroyed      {}
//   path:chosen         { path }
//   stats:changed       { stats }
//   passive:toggled     { active }

class EventBus {
  constructor() {
    this._listeners = new Map();
  }

  on(channel, fn) {
    if (!this._listeners.has(channel)) this._listeners.set(channel, new Set());
    this._listeners.get(channel).add(fn);
    return () => this.off(channel, fn);
  }

  once(channel, fn) {
    const off = this.on(channel, (payload) => {
      off();
      fn(payload);
    });
    return off;
  }

  off(channel, fn) {
    this._listeners.get(channel)?.delete(fn);
  }

  emit(channel, payload = {}) {
    const set = this._listeners.get(channel);
    if (!set) return;
    for (const fn of [...set]) {
      try {
        fn(payload);
      } catch (err) {
        console.error(`[EventBus] listener error on "${channel}"`, err);
      }
    }
  }
}

export const bus = new EventBus();
