export class NaturalSort {
  static compare(a: string, b: string): number {
    const left = a.toLowerCase();
    const right = b.toLowerCase();
    let i = 0;
    let j = 0;
    while (i < left.length && j < right.length) {
      const ca = left.charAt(i);
      const cb = right.charAt(j);
      const digitA = ca >= '0' && ca <= '9';
      const digitB = cb >= '0' && cb <= '9';
      if (digitA && digitB) {
        let ni = i;
        while (ni < left.length && left.charAt(ni) >= '0' && left.charAt(ni) <= '9') {
          ni++;
        }
        let nj = j;
        while (nj < right.length && right.charAt(nj) >= '0' && right.charAt(nj) <= '9') {
          nj++;
        }
        const na = Number.parseInt(left.substring(i, ni), 10);
        const nb = Number.parseInt(right.substring(j, nj), 10);
        if (na !== nb) {
          return na - nb;
        }
        i = ni;
        j = nj;
      } else {
        if (ca < cb) {
          return -1;
        }
        if (ca > cb) {
          return 1;
        }
        i++;
        j++;
      }
    }
    return left.length - right.length;
  }
}
