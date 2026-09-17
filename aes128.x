// AES-128 (FIPS-197) encryption implemented in DSLX.
//
// Provides:
//   - key_expansion(key)         : AES-128 key schedule (11 round keys)
//   - aes128_encrypt(input, key) : single 16-byte block encryption
//
// State / key convention: 16-byte arrays are treated column-major,
// i.e. byte i corresponds to state[row][col] with row = i % 4, col = i / 4,
// matching the FIPS-197 definition (bytes fill the state column by column).

// ---------------------------------------------------------------------
// Constant tables
// ---------------------------------------------------------------------

pub const SBOX: u8[256] = [
    u8:0x63, u8:0x7c, u8:0x77, u8:0x7b, u8:0xf2, u8:0x6b, u8:0x6f, u8:0xc5,
    u8:0x30, u8:0x01, u8:0x67, u8:0x2b, u8:0xfe, u8:0xd7, u8:0xab, u8:0x76,
    u8:0xca, u8:0x82, u8:0xc9, u8:0x7d, u8:0xfa, u8:0x59, u8:0x47, u8:0xf0,
    u8:0xad, u8:0xd4, u8:0xa2, u8:0xaf, u8:0x9c, u8:0xa4, u8:0x72, u8:0xc0,
    u8:0xb7, u8:0xfd, u8:0x93, u8:0x26, u8:0x36, u8:0x3f, u8:0xf7, u8:0xcc,
    u8:0x34, u8:0xa5, u8:0xe5, u8:0xf1, u8:0x71, u8:0xd8, u8:0x31, u8:0x15,
    u8:0x04, u8:0xc7, u8:0x23, u8:0xc3, u8:0x18, u8:0x96, u8:0x05, u8:0x9a,
    u8:0x07, u8:0x12, u8:0x80, u8:0xe2, u8:0xeb, u8:0x27, u8:0xb2, u8:0x75,
    u8:0x09, u8:0x83, u8:0x2c, u8:0x1a, u8:0x1b, u8:0x6e, u8:0x5a, u8:0xa0,
    u8:0x52, u8:0x3b, u8:0xd6, u8:0xb3, u8:0x29, u8:0xe3, u8:0x2f, u8:0x84,
    u8:0x53, u8:0xd1, u8:0x00, u8:0xed, u8:0x20, u8:0xfc, u8:0xb1, u8:0x5b,
    u8:0x6a, u8:0xcb, u8:0xbe, u8:0x39, u8:0x4a, u8:0x4c, u8:0x58, u8:0xcf,
    u8:0xd0, u8:0xef, u8:0xaa, u8:0xfb, u8:0x43, u8:0x4d, u8:0x33, u8:0x85,
    u8:0x45, u8:0xf9, u8:0x02, u8:0x7f, u8:0x50, u8:0x3c, u8:0x9f, u8:0xa8,
    u8:0x51, u8:0xa3, u8:0x40, u8:0x8f, u8:0x92, u8:0x9d, u8:0x38, u8:0xf5,
    u8:0xbc, u8:0xb6, u8:0xda, u8:0x21, u8:0x10, u8:0xff, u8:0xf3, u8:0xd2,
    u8:0xcd, u8:0x0c, u8:0x13, u8:0xec, u8:0x5f, u8:0x97, u8:0x44, u8:0x17,
    u8:0xc4, u8:0xa7, u8:0x7e, u8:0x3d, u8:0x64, u8:0x5d, u8:0x19, u8:0x73,
    u8:0x60, u8:0x81, u8:0x4f, u8:0xdc, u8:0x22, u8:0x2a, u8:0x90, u8:0x88,
    u8:0x46, u8:0xee, u8:0xb8, u8:0x14, u8:0xde, u8:0x5e, u8:0x0b, u8:0xdb,
    u8:0xe0, u8:0x32, u8:0x3a, u8:0x0a, u8:0x49, u8:0x06, u8:0x24, u8:0x5c,
    u8:0xc2, u8:0xd3, u8:0xac, u8:0x62, u8:0x91, u8:0x95, u8:0xe4, u8:0x79,
    u8:0xe7, u8:0xc8, u8:0x37, u8:0x6d, u8:0x8d, u8:0xd5, u8:0x4e, u8:0xa9,
    u8:0x6c, u8:0x56, u8:0xf4, u8:0xea, u8:0x65, u8:0x7a, u8:0xae, u8:0x08,
    u8:0xba, u8:0x78, u8:0x25, u8:0x2e, u8:0x1c, u8:0xa6, u8:0xb4, u8:0xc6,
    u8:0xe8, u8:0xdd, u8:0x74, u8:0x1f, u8:0x4b, u8:0xbd, u8:0x8b, u8:0x8a,
    u8:0x70, u8:0x3e, u8:0xb5, u8:0x66, u8:0x48, u8:0x03, u8:0xf6, u8:0x0e,
    u8:0x61, u8:0x35, u8:0x57, u8:0xb9, u8:0x86, u8:0xc1, u8:0x1d, u8:0x9e,
    u8:0xe1, u8:0xf8, u8:0x98, u8:0x11, u8:0x69, u8:0xd9, u8:0x8e, u8:0x94,
    u8:0x9b, u8:0x1e, u8:0x87, u8:0xe9, u8:0xce, u8:0x55, u8:0x28, u8:0xdf,
    u8:0x8c, u8:0xa1, u8:0x89, u8:0x0d, u8:0xbf, u8:0xe6, u8:0x42, u8:0x68,
    u8:0x41, u8:0x99, u8:0x2d, u8:0x0f, u8:0xb0, u8:0x54, u8:0xbb, u8:0x16,
];

// Round constants used in the key schedule (index 0 => Rcon[1] in FIPS-197).
pub const RCON: u8[10] = [
    u8:0x01, u8:0x02, u8:0x04, u8:0x08, u8:0x10,
    u8:0x20, u8:0x40, u8:0x80, u8:0x1b, u8:0x36,
];

// ---------------------------------------------------------------------
// GF(2^8) arithmetic
// ---------------------------------------------------------------------

// Multiply by x (i.e. by 2) modulo the AES reduction polynomial.
fn xtime(a: u8) -> u8 {
    let hi_bit_set = (a & u8:0x80) != u8:0;
    let shifted = a << u8:1;
    if hi_bit_set { shifted ^ u8:0x1b } else { shifted }
}

// General GF(2^8) multiply via shift-and-add ("Russian peasant" method).
fn gmul(a: u8, b: u8) -> u8 {
    let (result, _, _) = for (i, tup): (u32, (u8, u8, u8)) in u32:0..u32:8 {
        let (acc, aa, bb) = tup;
        let bit_set = (bb & u8:1) != u8:0;
        let new_acc = if bit_set { acc ^ aa } else { acc };
        let new_aa = xtime(aa);
        let new_bb = bb >> u8:1;
        (new_acc, new_aa, new_bb)
    }((u8:0, a, b));
    result
}

// ---------------------------------------------------------------------
// Key schedule helpers (a "word" is 4 bytes)
// ---------------------------------------------------------------------

fn sub_word(w: u8[4]) -> u8[4] {
    [SBOX[w[0] as u32], SBOX[w[1] as u32], SBOX[w[2] as u32], SBOX[w[3] as u32]]
}

fn rot_word(w: u8[4]) -> u8[4] {
    [w[1], w[2], w[3], w[0]]
}

fn xor_word(a: u8[4], b: u8[4]) -> u8[4] {
    [a[0] ^ b[0], a[1] ^ b[1], a[2] ^ b[2], a[3] ^ b[3]]
}

// AES-128 key expansion: 4-byte key -> 44 words (11 round keys of 4 words).
pub fn key_expansion(key: u8[16]) -> u8[4][44] {
    let w0: u8[4] = [key[0], key[1], key[2], key[3]];
    let w1: u8[4] = [key[4], key[5], key[6], key[7]];
    let w2: u8[4] = [key[8], key[9], key[10], key[11]];
    let w3: u8[4] = [key[12], key[13], key[14], key[15]];

    let init_words: u8[4][44] = [[u8:0, u8:0, u8:0, u8:0], ...];
    let words0 = update(init_words, u32:0, w0);
    let words1 = update(words0, u32:1, w1);
    let words2 = update(words1, u32:2, w2);
    let words3 = update(words2, u32:3, w3);

    for (i, words): (u32, u8[4][44]) in u32:4..u32:44 {
        let temp = words[i - u32:1];
        let temp2 = if i % u32:4 == u32:0 {
            let rotated = rot_word(temp);
            let subbed = sub_word(rotated);
            let rc: u8[4] = [RCON[i / u32:4 - u32:1], u8:0, u8:0, u8:0];
            xor_word(subbed, rc)
        } else {
            temp
        };
        let new_word = xor_word(words[i - u32:4], temp2);
        update(words, i, new_word)
    }(words3)
}

// Pull out the 4 words (16 bytes) used for a given round (0..=10).
fn get_round_key(expanded: u8[4][44], round: u32) -> u8[4][4] {
    [
        expanded[round * u32:4],
        expanded[round * u32:4 + u32:1],
        expanded[round * u32:4 + u32:2],
        expanded[round * u32:4 + u32:3],
    ]
}

// ---------------------------------------------------------------------
// Round transformations (state is 16 bytes, column-major)
// ---------------------------------------------------------------------

fn sub_bytes(state: u8[16]) -> u8[16] {
    for (i, acc): (u32, u8[16]) in u32:0..u32:16 {
        update(acc, i, SBOX[state[i] as u32])
    }(state)
}

fn shift_rows(state: u8[16]) -> u8[16] {
    for (i, acc): (u32, u8[16]) in u32:0..u32:16 {
        let r = i % u32:4;
        let c = i / u32:4;
        let src_c = (c + r) % u32:4;
        let src_i = r + u32:4 * src_c;
        update(acc, i, state[src_i])
    }(state)
}

fn mix_columns(state: u8[16]) -> u8[16] {
    for (c, acc): (u32, u8[16]) in u32:0..u32:4 {
        let base = u32:4 * c;
        let s0 = state[base];
        let s1 = state[base + u32:1];
        let s2 = state[base + u32:2];
        let s3 = state[base + u32:3];
        let r0 = gmul(s0, u8:2) ^ gmul(s1, u8:3) ^ s2 ^ s3;
        let r1 = s0 ^ gmul(s1, u8:2) ^ gmul(s2, u8:3) ^ s3;
        let r2 = s0 ^ s1 ^ gmul(s2, u8:2) ^ gmul(s3, u8:3);
        let r3 = gmul(s0, u8:3) ^ s1 ^ s2 ^ gmul(s3, u8:2);
        let acc1 = update(acc, base, r0);
        let acc2 = update(acc1, base + u32:1, r1);
        let acc3 = update(acc2, base + u32:2, r2);
        update(acc3, base + u32:3, r3)
    }(state)
}

fn add_round_key(state: u8[16], round_key: u8[4][4]) -> u8[16] {
    for (i, acc): (u32, u8[16]) in u32:0..u32:16 {
        let c = i / u32:4;
        let r = i % u32:4;
        update(acc, i, state[i] ^ round_key[c][r])
    }(state)
}

// ---------------------------------------------------------------------
// Top-level AES-128 single-block encryption
// ---------------------------------------------------------------------

pub fn aes128_encrypt(input: u8[16], key: u8[16]) -> u8[16] {
    let expanded_key = key_expansion(key);
    let state0 = add_round_key(input, get_round_key(expanded_key, u32:0));

    // Rounds 1..9: SubBytes -> ShiftRows -> MixColumns -> AddRoundKey.
    let state9 = for (round, state): (u32, u8[16]) in u32:1..u32:10 {
        let s1 = sub_bytes(state);
        let s2 = shift_rows(s1);
        let s3 = mix_columns(s2);
        add_round_key(s3, get_round_key(expanded_key, round))
    }(state0);

    // Final round 10: SubBytes -> ShiftRows -> AddRoundKey (no MixColumns).
    let final_sub = sub_bytes(state9);
    let final_shift = shift_rows(final_sub);
    add_round_key(final_shift, get_round_key(expanded_key, u32:10))
}

// ---------------------------------------------------------------------
// Test: FIPS-197 Appendix B / C.1 known-answer vector
//   key        = 000102030405060708090a0b0c0d0e0f
//   plaintext  = 00112233445566778899aabbccddeeff
//   ciphertext = 69c4e0d86a7b0430d8cdb78070b4c55a
// ---------------------------------------------------------------------

#[test]
fn test_aes128_fips_vector() {
    let key: u8[16] = [
        u8:0x00, u8:0x01, u8:0x02, u8:0x03, u8:0x04, u8:0x05, u8:0x06, u8:0x07,
        u8:0x08, u8:0x09, u8:0x0a, u8:0x0b, u8:0x0c, u8:0x0d, u8:0x0e, u8:0x0f,
    ];
    let plaintext: u8[16] = [
        u8:0x00, u8:0x11, u8:0x22, u8:0x33, u8:0x44, u8:0x55, u8:0x66, u8:0x77,
        u8:0x88, u8:0x99, u8:0xaa, u8:0xbb, u8:0xcc, u8:0xdd, u8:0xee, u8:0xff,
    ];
    let expected_ct: u8[16] = [
        u8:0x69, u8:0xc4, u8:0xe0, u8:0xd8, u8:0x6a, u8:0x7b, u8:0x04, u8:0x30,
        u8:0xd8, u8:0xcd, u8:0xb7, u8:0x80, u8:0x70, u8:0xb4, u8:0xc5, u8:0x5a,
    ];

    let ct = aes128_encrypt(plaintext, key);
    assert_eq(ct, expected_ct)
}