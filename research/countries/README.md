# Country rules for tremulator: all 195

Built 2026-09-21. **Open [countries_195.tsv](countries_195.tsv)**: one row per UN
member or observer state, with its encryption, transfer, storage and health-data
rules and the source for each.

## What was measured, and from where

| Question | Source | Coverage |
|---|---|---|
| Is encryption restricted? | Global Partners Digital, *World map of encryption laws and policies*, gp-digital.org, fetched 2026-09-21 (`gpd.html`). Undated; the newest law it cites is from 2021. | all 195 (plus Taiwan, dropped) |
| May personal data leave the country? | DLA Piper, *Data Protection Laws of the World*, dlapiperdataprotection.com, fetched 2026-09-21. Pages last modified between 2021 and March 2026, per row. | 146 of 195 |
| Must data be stored in the country? | same, every section searched, not only the transfer section | 146 of 195 |
| Is health data a sensitive category? | same, definitions section | 146 of 195 |
| The 195 | United Nations, *Member States*, un.org, fetched 2026-09-21: 193 members plus the Holy See and the State of Palestine | 195 |

Tried and blocked: UNCTAD's *Data Protection and Privacy Legislation Worldwide*
returned HTTP 403 to every request.

## Results

| | Count |
|---|---|
| Encryption: widespread restrictions | 13: China, Colombia, Cuba, Egypt, India, Iran, Kazakhstan, Montenegro, Morocco, Pakistan, Russia, Syria, Viet Nam |
| Encryption: some restrictions | 57 |
| Encryption: minimal restrictions | 19 |
| Encryption: no information (GPD never researched these; **not** "no rules") | 106 |
| Encryption licensing or registration rules | 23 (listed in `summary_counts.txt`) |
| Transfer abroad allowed on conditions (adequacy, contract, consent) | 111 of 146 |
| Transfer needs a regulator's prior authorisation | 18 of 146 |
| No general transfer restriction | 15 of 146 |
| **Data must stay in the country** | **at least 10 of 146**: general rule in Kazakhstan, Mongolia, Russia, Rwanda, Turkmenistan (local copy), Uzbekistan; health-specific in Kenya (a local copy suffices), Slovenia, the UAE, Zambia. **A floor**: DLA omitted Kenya's, see Limits |
| Health data is a sensitive category | 123 of 146; 19 have no sensitive category at all; 3 not stated; Canada only in Quebec |
| A life, vital-interest or health-emergency exception appears in DLA's transfer text | 59 of 146 (the other 87 = DLA does not mention one, **not** proof the law lacks it) |
| Not covered by DLA Piper | 49, including Afghanistan, Iraq, Malawi, Somalia, South Sudan, Sudan, Syria, Yemen |

## What it means for the defaults

- **Data location.** At least 10 of 146 impose a storage-location rule; DLA's
  summaries mention none for the other 136, which is not proof there are none. The 10
  are all satisfied by the design as it stands: the ground server is in the
  country and the cloud peer is optional. Default stays: ground server required,
  cloud optional. A group deploying in one of the 9 puts its cloud peer in that
  country or runs without one. Every group checks its own country's health
  regulations directly, because DLA misses rules like Kenya's.
- **Sending clinical content to a foreign consultant** is a regulated transfer
  in 131 of 146 countries, allowed on conditions in nearly all of them. That is
  the use case itself, so there is nothing for software to switch off; the legal
  basis is the deploying group's to establish.
- **Health data** is sensitive in 123 of 146, so the software treats all
  clinical content as sensitive everywhere. It already does: end-to-end
  encryption, keys destroyed on purge.
- **Encryption** cannot be switched off, and should not be. The 13 with
  widespread restrictions and the 23 with licensing rules are the countries to
  check before a deployment. For 106 countries there is no information.

## How the classifications were made

1. `extract_gpd.py` parses the saved GPD page. Checked against known cases:
   China, Russia, Iran, Pakistan come out "widespread"; the United States
   "minimal".
2. `fetch_dla.py` fetched all 164 DLA jurisdictions (164 × HTTP 200, 13 sections
   each; raw pages archived in `dla_raw.tar.gz`).
3. `classify_dla.py` made a keyword first pass. **It was wrong often:** it
   called 8 countries "must stay in country" and the hand reading found 2; it
   called 43 "authorisation needed" and the reading found 18, because every GDPR
   country mentions a supervisory authority somewhere. Its health column first
   found 29 of 164 because DLA breaks lines at quotation marks; fixed, it found
   26 of 27 EU members, and the 27th (Slovenia) was confirmed by hand.
4. **Every one of the 164 transfer sections was read by hand** and classified in
   `dla_reviewed.tsv` with a note.
5. `sweep_localisation.py` searched every section of every jurisdiction for
   storage-location language. Its first version missed Rwanda's Article 50; a
   probe for known positives caught that and the sweep was fixed. All 130 hits
   were read; `localisation_review.tsv` records the result.
6. Health: all 43 first-pass "no" rows and the 28 "yes" rows whose saved evidence
   was cut off were read by hand (`build_health_final.py`).
7. `build_master.py` joins everything onto the 195 with explicit name aliases
   and fails if any country is unmatched in GPD.

## Limits

- These are two firms' **summaries of the law**, not the laws. A deployment
  still reads the actual law of its country.
- GPD is undated and probably current to about 2021.
- DLA pages vary in age; each row carries its last-modified date.
- **DLA misses health storage rules.** Kenya's Data Protection (General)
  Regulations, Legal Notice 263 of 2021, regulation 26(2)(f), require data
  processed for primary or secondary health care to be handled on a server in
  Kenya or kept as a copy there. DLA's Kenya page (last modified 2026) does not
  mention it. It was read directly from Kenya Law and added by hand. Other
  countries may have health-sector rules DLA also omits; only Kenya was checked
  this way.
- A column for a medical-care legal basis was generated by keyword and **not
  reviewed**; it is not in the final table and nothing depends on it.
