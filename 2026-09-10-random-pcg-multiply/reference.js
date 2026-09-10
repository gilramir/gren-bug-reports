const M = 1n << 32n;
const mask = M - 1n;
const next = ([s, inc]) => [(s * 1664525n + inc) & mask, inc];
const peel = ([s]) => {
  const shift = ((s >> 28n) + 4n);
  const word = ((s ^ (s >> shift)) * 277803737n) & mask;
  return ((word >> 22n) ^ word) & mask;
};
const initialSeed = (x) => {
  let sd = next([0n, 1013904223n]);
  return next([(sd[0] + BigInt(x)) & mask, sd[1]]);
};
function ints(lo, hi, seedN, count) {
  const range = BigInt(hi - lo + 1);
  let seed = initialSeed(seedN);
  const out = [];
  const threshhold = M % range;
  for (let i = 0; i < count; i++) {
    let x;
    for (;;) { x = peel(seed); seed = next(seed); if (x >= threshhold) break; }
    out.push((x % range + BigInt(lo)).toString());
  }
  return out.join(" ");
}
console.log("true PCG, d6 seed 7      :", ints(1, 6, 7, 8));
console.log("true PCG, d6 seed 0      :", ints(1, 6, 0, 8));
console.log("true PCG, wide range s=11:", ints(-1000000, 1000000, 11, 8));
