// Generic finite state machine, used at two levels:
//   - GameDirector (CREATION → OFFICE → CITY_EXIT → WILDS → ...)
//   - CharacterCreationState (ORIGIN → BODY → FACE → CLASS → CONFIRM)
// States are plain objects: { enter(ctx, from), exit(ctx, to), update(ctx, dt) } — all optional.

export class StateMachine {
  constructor(name, ctx = {}) {
    this.name = name;
    this.ctx = ctx;
    this.states = new Map();
    this.current = null;
    this.currentId = null;
    this.history = [];
  }

  add(id, state) {
    this.states.set(id, state);
    return this;
  }

  go(id, payload) {
    if (id === this.currentId) return;
    const next = this.states.get(id);
    if (!next) {
      console.error(`[FSM:${this.name}] unknown state "${id}"`);
      return;
    }
    const fromId = this.currentId;
    this.current?.exit?.(this.ctx, id);
    this.history.push(id);
    this.currentId = id;
    this.current = next;
    console.log(`[FSM:${this.name}] ${fromId ?? "∅"} → ${id}`);
    next.enter?.(this.ctx, fromId, payload);
  }

  update(dt) {
    this.current?.update?.(this.ctx, dt);
  }

  is(id) {
    return this.currentId === id;
  }
}
