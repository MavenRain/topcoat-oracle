// The js side of the M28 planted oracle (spec section 7).  A closed
// table keyed by name: an unknown name is null and the caller turns
// that into a usage error, so a typo can never run unplanted.
//
// The module imports NOTHING from the clone.  worker.mjs owns the
// clone classes and hands them over as a kit, the way lib/value.mjs
// takes its classifier as an argument.  That is what lets
// test/plant.test.mjs import this file with two hand-written stubs.

/** The one js plant name. */
export const SIGNAL_GET_PLUS_ONE = "signal_get_plus_one";

const PLANTS = Object.freeze({
  [SIGNAL_GET_PLUS_ONE]: Object.freeze({ name: SIGNAL_GET_PLUS_ONE }),
});

/**
 * Look one plant up by name.
 * @param {string} name the plant name, with no "js:" prefix
 * @returns {{name: string} | null} the plant, or null for an unknown name
 */
export const plantOfName = (name) =>
  Object.hasOwn(PLANTS, name) === true ? PLANTS[name] : null;

/**
 * Wrap one hydrated surrogate so a signal READ returns value + 1.
 * @param {unknown} produced whatever cx.hydrate produced
 * @param {object} kit isSignal, isNumber and plusOne over the clone
 * @returns {unknown} the wrapped surrogate, or the input unchanged
 */
const plantedSurrogate = (produced, kit) =>
  kit.isSignal(produced) === false
    ? produced
    : Object.create(produced, {
        get: {
          value: () =>
            ((read) => (kit.isNumber(read) === false ? read : kit.plusOne(read)))(
              produced.get(),
            ),
        },
      });

/**
 * Wrap one Context so hydrated signals carry the plant.
 * @param {object} cx the real Context
 * @param {{name: string} | null} plant the selected plant, or null
 * @param {object} kit isSignal, isNumber and plusOne over the clone
 * @returns {object} the Context the emitted body is given
 */
export const plantedContext = (cx, plant, kit) =>
  plant === null
    ? cx
    : Object.create(cx, {
        hydrate: {
          value: (s) => plantedSurrogate(cx.hydrate(s), kit),
        },
      });
