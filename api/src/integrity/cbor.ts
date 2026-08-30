/**
 * Just enough CBOR to read what App Attest sends: the attestation object and
 * the assertion. Both are small maps of byte strings, text, arrays, and
 * unsigned integers, so the decoder covers major types 0–5 and refuses
 * anything else rather than guessing.
 */

export type CborValue =
  | number
  | string
  | Uint8Array
  | CborValue[]
  | { [key: string]: CborValue };

class Reader {
  private offset = 0;
  private readonly bytes: Uint8Array;

  constructor(bytes: Uint8Array) {
    this.bytes = bytes;
  }

  get consumed(): number {
    return this.offset;
  }

  private take(count: number): Uint8Array {
    if (this.offset + count > this.bytes.length) {
      throw new Error("cbor: unexpected end of input");
    }
    const slice = this.bytes.subarray(this.offset, this.offset + count);
    this.offset += count;
    return slice;
  }

  private uint(additional: number): number {
    if (additional < 24) return additional;
    if (additional === 24) return this.take(1)[0]!;
    if (additional === 25) {
      const bytes = this.take(2);
      return (bytes[0]! << 8) | bytes[1]!;
    }
    if (additional === 26) {
      const bytes = this.take(4);
      return ((bytes[0]! << 24) >>> 0) + (bytes[1]! << 16) + (bytes[2]! << 8) + bytes[3]!;
    }
    if (additional === 27) {
      const bytes = this.take(8);
      let value = 0;
      for (const byte of bytes) value = value * 256 + byte;
      if (!Number.isSafeInteger(value)) throw new Error("cbor: integer out of range");
      return value;
    }
    throw new Error(`cbor: unsupported length encoding ${additional}`);
  }

  value(): CborValue {
    const initial = this.take(1)[0]!;
    const major = initial >> 5;
    const additional = initial & 0x1f;

    switch (major) {
      case 0:
        return this.uint(additional);
      case 1:
        return -1 - this.uint(additional);
      case 2:
        return new Uint8Array(this.take(this.uint(additional)));
      case 3:
        return new TextDecoder().decode(this.take(this.uint(additional)));
      case 4: {
        const length = this.uint(additional);
        const items: CborValue[] = [];
        for (let index = 0; index < length; index += 1) items.push(this.value());
        return items;
      }
      case 5: {
        const length = this.uint(additional);
        const map: { [key: string]: CborValue } = {};
        for (let index = 0; index < length; index += 1) {
          const key = this.value();
          if (typeof key !== "string") throw new Error("cbor: only text map keys are supported");
          map[key] = this.value();
        }
        return map;
      }
      default:
        throw new Error(`cbor: unsupported major type ${major}`);
    }
  }
}

export function decodeCbor(bytes: Uint8Array): CborValue {
  const reader = new Reader(bytes);
  const value = reader.value();
  if (reader.consumed !== bytes.length) {
    throw new Error("cbor: trailing bytes");
  }
  return value;
}
