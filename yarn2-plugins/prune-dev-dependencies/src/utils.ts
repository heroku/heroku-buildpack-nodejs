/* eslint-disable */

// Decorates a class with the specified metadata. Code borrowed from esbuild.
export const decorateClass = (decorators, target, key: string) => {
  let result = target

  for (let i = decorators.length - 1, decorator; i >= 0; i--) {
    decorator = decorators[i]
    if (decorator) {
      result = decorator(target, key, result) || result
    }
  }

  if (result) {
    Object.defineProperty(target, key, result)
  }

  return result
}
