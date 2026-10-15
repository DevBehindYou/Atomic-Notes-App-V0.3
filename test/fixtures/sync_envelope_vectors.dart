// Fixed public vectors; CI verifies expectations with actual locked Server source.
const syncEnvelopeVectorsJson = r'''[
  {
    "case": "C1 standard Unicode default version",
    "mode": "standard",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "text",
        "title": "Public synthetic",
        "body": "\u03a9 \ud83d\ude00",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null,
        "user_id": "ignored-public"
      }
    ],
    "expected": {
      "fingerprint": "3bba48c05f7cc5467f4b498d72be9e62c4ec60165da07369c198a2d038d22a3c",
      "wireBytes": 307,
      "wireSha256": "e87b64882fdcfdb9f5704e6f62da1348cbc8786ab11882d6b8eea205a8d739bd",
      "projectedSha256": "07ee07b0777026e692c4194f4cfeec90af1e2ad6443429bdad3b010227e7a0b9"
    }
  },
  {
    "case": "C2 instant Unicode default version",
    "mode": "instant",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "text",
        "title": "Public synthetic",
        "body": "\u03a9 \ud83d\ude00",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null
      }
    ],
    "expected": {
      "fingerprint": "98f853f6a8c0404e9fdc693553ed7430753d6f6a1d0261d535847a38be55f1a6",
      "wireBytes": 306,
      "wireSha256": "0634c8e366ddada690ba431ce4b5ccb6b9d5c41c0f18edd743c1550f21b18cb9",
      "projectedSha256": "07ee07b0777026e692c4194f4cfeec90af1e2ad6443429bdad3b010227e7a0b9"
    }
  },
  {
    "case": "C3 compact checklist and optional time",
    "mode": "standard",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "todo",
        "title": "Public synthetic",
        "body": "\u03a9 \ud83d\ude00",
        "items": [
          {
            "t": "Public task",
            "d": true
          }
        ],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null,
        "updated_at": "2026-10-14T01:02:03.004Z",
        "base_version": 3
      }
    ],
    "expected": {
      "fingerprint": "3445bfc0d6e330a1dd7853dd6f5ef11461672ee5fcf9b3fda726d49b49927310",
      "wireBytes": 381,
      "wireSha256": "ea5340af817d6080caa52e73b100df32c35ac050db612f46fe91b2c970ea7edf",
      "projectedSha256": "e7c6229a3b1a7623b7f847a496a4ea4431fab41fc7e3cddb757f0a74a16f8118"
    }
  },
  {
    "case": "C4 shuffled keys project to Server order",
    "mode": "instant",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "base_version": 4,
        "payload": null,
        "enc_v": 0,
        "created_at": "2026-10-14T00:00:00.000Z",
        "deleted": false,
        "pinned": false,
        "items": [],
        "body": "\u03a9 \ud83d\ude00",
        "title": "Public synthetic",
        "kind": "text",
        "id": "00000000-0000-4000-8000-000000000003",
        "unknown": "stripped"
      }
    ],
    "expected": {
      "fingerprint": "e2e33abab5c0d116fe8a69aa4bc7ae516fed8094f4a759e1c95afb8644861d26",
      "wireBytes": 306,
      "wireSha256": "f932a5a33012a0697c99fd62643c9d66e9e379e64bbfb241717b8246ca62930f",
      "projectedSha256": "9edf71c7481087bd63fd56c72f5a25b3a224689905ca94c436aaf82654af1f9b"
    }
  },
  {
    "case": "C5 sealed standard payload",
    "mode": "standard",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "text",
        "title": "",
        "body": "",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 1,
        "payload": "public-synthetic-ciphertext"
      }
    ],
    "expected": {
      "fingerprint": "d445be9954c3ce516fbd693399c7473da3fa99c89ea61ddd1d2532b9938b81c1",
      "wireBytes": 309,
      "wireSha256": "d22544f8781f201a77fcd27ab4cf424e9f1782fc5a3513de14121ae6d6800aad",
      "projectedSha256": "a16f507c34a194412da686cc724d192cc89e4bc215b72955bd051f61521087ba"
    }
  },
  {
    "case": "C6 instant tombstone",
    "mode": "instant",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "text",
        "title": "Public synthetic",
        "body": "\u03a9 \ud83d\ude00",
        "items": [],
        "pinned": false,
        "deleted": true,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null,
        "base_version": 8
      }
    ],
    "expected": {
      "fingerprint": "ec6b6d196b857273f4c1de61af1d889aafbb332b52b1838971555fc790813d2d",
      "wireBytes": 305,
      "wireSha256": "86027b870ba6147014094e11afb30bb63e26d4c07f341753d96e271ab1e78853",
      "projectedSha256": "92e0fa2cbd6ec6a6dbbe963c6472845312d164132ebbb4898249e48a5d8ae444"
    }
  },
  {
    "case": "C7 UTF16 escaping and controls",
    "mode": "standard",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "text",
        "title": "Public synthetic",
        "body": "\"\\\b\t\n\f\r\u0000\u001f/\u2028\u2029\ud83d\ude00\ud800X\udfff",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null
      }
    ],
    "expected": {
      "fingerprint": "a86d7d8207427a423015a76d300ba7d1173c2443aa1f28850540f0d2f1d3b550",
      "wireBytes": 350,
      "wireSha256": "2ab2dec311425d380fdeaf545938440a0f282702b6ffee2d9ffa1e56483c6535",
      "projectedSha256": "bcaec4924980aa221df50ae4db6d1ce6d39fbfea82913f2e14cb35e129336387"
    }
  },
  {
    "case": "C8 maximum safe version",
    "mode": "instant",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "text",
        "title": "Public synthetic",
        "body": "\u03a9 \ud83d\ude00",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null,
        "base_version": 9007199254740991
      }
    ],
    "expected": {
      "fingerprint": "09e9261ffb603b5ad3ef96566d1ca9de9bcedaf59ef82b028d9dbe1b4edcb2af",
      "wireBytes": 321,
      "wireSha256": "d6651fdea2e97523458a5abadf4e4499b0cdb4fcddc4921aacc56147f894d6b1",
      "projectedSha256": "3a05480f7fe9fe1523d6683826933e4fde44d53c4a2f99a293ad1ea49041602f"
    }
  },
  {
    "case": "C9 ordered two row envelope",
    "mode": "standard",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "text",
        "title": "Public synthetic",
        "body": "\u03a9 \ud83d\ude00",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null
      },
      {
        "id": "00000000-0000-4000-8000-000000000005",
        "kind": "text",
        "title": "Public synthetic",
        "body": "Second row",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null
      }
    ],
    "expected": {
      "fingerprint": "d671de5e70ec43b2fc1c912f05fd48b8fab792e281d1acf5a15ab4d62afbc084",
      "wireBytes": 538,
      "wireSha256": "5bed4a460b72f1f16c41ac72812f30d720818c3cc513e8b0f034787e677b831e",
      "projectedSha256": "49169cb0f45117b5f9647fe386c897d82040cd6020fa08527039f5c1dac6c6b0"
    }
  },
  {
    "case": "C10 reversed two row envelope",
    "mode": "standard",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000005",
        "kind": "text",
        "title": "Public synthetic",
        "body": "Second row",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null
      },
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "text",
        "title": "Public synthetic",
        "body": "\u03a9 \ud83d\ude00",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null
      }
    ],
    "expected": {
      "fingerprint": "c1335b4c811c24a8b30b9381ca12be734903ec9906bce4856974a37a9df4bda9",
      "wireBytes": 538,
      "wireSha256": "b7ec60889a3f35916509e356d3fa81f2522d32dd5504826251c2f5399f1ffc7e",
      "projectedSha256": "6c94b6cd2b1ca2bb10f0bd8173dafac181cfb381a3971a9859e69733a4f74bdf"
    }
  },
  {
    "case": "C11 offset and fractional dates preserved",
    "mode": "instant",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "text",
        "title": "Public synthetic",
        "body": "\u03a9 \ud83d\ude00",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null,
        "updated_at": "2026-10-14T01:02:03.004+05:30"
      }
    ],
    "expected": {
      "fingerprint": "271ebcc745fc0bd3a8b9d7e797649f8cc837f213fac3e33de05448ed40ff7c7f",
      "wireBytes": 351,
      "wireSha256": "bbd25f0032690d91d37fd5bd457be50dcbc3795289d9782ad69fca5788005d94",
      "projectedSha256": "8490582cf903c89249acde4c0021a3268ada7727a5da1a4a3ffbe00ef6118d28"
    }
  },
  {
    "case": "C12 literal escaping and checklist fields",
    "mode": "standard",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "todo",
        "title": "Public synthetic",
        "body": "\u03a9 \ud83d\ude00",
        "items": [
          {
            "text": "\"\\ \u03a9\ud83d\ude00",
            "done": false
          }
        ],
        "pinned": true,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null
      }
    ],
    "expected": {
      "fingerprint": "ded5a164eb3c8a6ef501bd9ef51d83cc8f20b492597ab5cd022516712bc41e3e",
      "wireBytes": 341,
      "wireSha256": "52f3d2fcf5a35e0881ca98885a0c611db415132d17cc629d18c21e958b38fe21",
      "projectedSha256": "5826dad98341beef0c7841fbbc05340802fa88e8029ed64963a74b286ec92978"
    }
  },
  {
    "case": "C13 unchanged logout unicode-default-version",
    "mode": "instant",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "text",
        "title": "Public synthetic logout",
        "body": "Public \u03a9 \ud83d\ude00",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-09T00:00:00.000Z",
        "enc_v": 0,
        "payload": null,
        "user_id": "untrusted-owner"
      }
    ],
    "attemptId": "00000000-0000-4000-8000-000000000004",
    "expected": {
      "fingerprint": "3d0f320eacd90a260d13f79860b50a66133e56a527cfba73f35a1a24a1c0b77b",
      "wireBytes": 377,
      "wireSha256": "469dc1995d1d3fa75919761027f8f5103c5e6f1dca6534591d383b948097ef47",
      "projectedSha256": "b1d9777ccf74652a2d64564ccba740378b1244d19886a74269407025dc562bd5"
    }
  },
  {
    "case": "C14 unchanged logout compact-checklist-and-version",
    "mode": "instant",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "todo",
        "title": "Public synthetic logout",
        "body": "Public \u03a9 \ud83d\ude00",
        "items": [
          {
            "t": "Public task",
            "d": false
          }
        ],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-09T00:00:00.000Z",
        "enc_v": 0,
        "payload": null,
        "base_version": 3
      }
    ],
    "attemptId": "00000000-0000-4000-8000-000000000004",
    "expected": {
      "fingerprint": "06edf5be3929ec3f37f9a303690c136fa4075def78820297f19f92547d53729c",
      "wireBytes": 412,
      "wireSha256": "3494356e2dd832d4ec55b28277ac798dbf9900d2aad71624eb3565d535898033",
      "projectedSha256": "449b42a1b546ddf586b5fe7f8980d9643a02d4dfa0c5558fadf3a7a9cb1617f0"
    }
  },
  {
    "case": "C15 unchanged logout ciphertext-and-time",
    "mode": "instant",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "text",
        "title": "",
        "body": "",
        "items": [],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-09T00:00:00.000Z",
        "enc_v": 1,
        "payload": "public-synthetic-ciphertext",
        "updated_at": "2026-10-09T00:00:01.000Z",
        "base_version": 4
      }
    ],
    "attemptId": "00000000-0000-4000-8000-000000000004",
    "expected": {
      "fingerprint": "852875b9a08cf8c882d542a502970b132634ba203f475af8b69a801b7680e6a2",
      "wireBytes": 405,
      "wireSha256": "911da5f0f9a721a4a054b115d3a336fff1fb4bd172882a01d27e590d2f6aeb8a",
      "projectedSha256": "093a0b91ffd2b1202cae14a82ebf8b9c98508f6478f8cdef47194e5b943dba95"
    }
  },
  {
    "case": "C21 complete checklist union branch owns ordinary aliases",
    "mode": "standard",
    "requestId": "00000000-0000-4000-8000-000000000002",
    "rows": [
      {
        "id": "00000000-0000-4000-8000-000000000003",
        "kind": "todo",
        "title": "Public synthetic",
        "body": "\u03a9 \ud83d\ude00",
        "items": [
          {
            "text": "A",
            "done": null,
            "t": "B",
            "d": true
          },
          {
            "text": 7,
            "done": true,
            "t": "C",
            "d": false
          },
          {
            "text": "Long",
            "done": false,
            "t": "Compact",
            "d": true
          }
        ],
        "pinned": false,
        "deleted": false,
        "created_at": "2026-10-14T00:00:00.000Z",
        "enc_v": 0,
        "payload": null
      }
    ],
    "expected": {
      "fingerprint": "843ac6ffdcaff5834263d07ebd30c7493d3c66d444827a40f34c4c5833b992c3",
      "wireBytes": 386,
      "wireSha256": "17b2ec3950f936766c211f11368c9d04ad5c4b5467797d57fdd15ea3bbdb4ccf",
      "projectedSha256": "5198d90e5c46fd0ca9ca63397e089b6b564dcc9aa44feabd36c977e45dcb7e15"
    }
  }
]''';
