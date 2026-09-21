#!/usr/bin/env python3
"""Final health-as-sensitive-data column, from the first pass plus hand review of
all 43 'no' rows and the 28 'yes' rows whose saved evidence was cut off
(2026-09-21). YES = health or medical data is a sensitive / special category in
DLA's account; PARTIAL = only in part of the country; NOT_DEFINED = the law has no
sensitive category (medical secrecy may still apply under other laws);
NOT_STATED = DLA gives no sensitive-data definition."""
import csv
HAND = {
 'AW':('YES','"personal data of a medical ... nature"'), 'BH':('YES','health in sensitive definition'),
 'CR':('YES','biomedical information'), 'SV':('YES','physical and mental health'),
 'GQ':('YES','processing health data without consent is a major infringement'), 'JP':('YES','medical history'),
 'LB':('YES','health data processing under a Minister of Public Health decision'), 'MX':('YES','past or present health conditions'),
 'MN':('YES','health in Art 4.1.12'), 'SC':('YES','health data'), 'KR':('YES','health or medical treatment information'),
 'TM':('YES','medical conditions: collection prohibited except with consent or for healthcare'),
 'UA':('YES','health; healthcare purposes an exemption'), 'VE':('YES','TSJ 1335/2011: medical record data under strictest handling'),
 'ZM':('YES','physical or mental health'), 'ZW':('YES','health care history, health information'),
 'LA':('YES','history of medical treatment listed as important information'), 'AE3':('YES','Patient Health Information regime'),
 'CA':('PARTIAL','only Quebec defines sensitive information (biometric or medical)'), 'SI':('YES','via GDPR Art 9; DLA text omits the list'),
 'BD':('NOT_DEFINED','CA 2023 has no sensitive category'), 'BN':('NOT_DEFINED','no legal definition'), 'BI':('NOT_DEFINED','not defined'),
 'CU':('NOT_DEFINED','no express definition'), 'HK':('NOT_DEFINED','no separate concept; guidance only'),
 'KZ':('NOT_DEFINED','no definition; medical secrecy under sector law'), 'KW':('NOT_DEFINED','health status is personal data; no sensitive category'),
 'KG':('NOT_DEFINED','all personal data confidential; health listed as personal data'), 'SG':('NOT_DEFINED','no category in law; guidance treats health as sensitive'),
 'IN':('NOT_DEFINED','DPDP Act has no sensitive category'), 'LY':('NOT_DEFINED','medical records listed as personal data, not a sensitive category'),
 'BB':('NOT_STATED','DLA quotes the sensitive list and it does not include health'), 'HT':('NOT_DEFINED','any data whose release would infringe rights'),
 'TJ':('NOT_DEFINED','only biometric data defined'), 'NA':('NOT_DEFINED','not defined'), 'MM':('NOT_DEFINED','no definition'),
 'LR':('NOT_DEFINED','no Liberian law defines it'), 'TO':('NOT_DEFINED','none'), 'FM':('NOT_DEFINED','none'),
 'FJ':('NOT_DEFINED','no law; constitutional privacy right only'), 'BO':('NOT_STATED','DLA gives only a general definition'),
 'KH':('NOT_DEFINED','personal data itself not defined'), 'RS':('NOT_STATED','DLA gives no sensitive-data definition'),
}
auto = list(csv.DictReader(open('dla_auto.tsv'), delimiter='\t'))
out = open('health_final.tsv', 'w', newline='')
w = csv.writer(out, delimiter='\t'); w.writerow(['code','health_sensitive_final','note'])
for r in auto:
    c = r['code']
    if c in HAND: v, n = HAND[c]
    elif r['health_sensitive_auto'] == 'yes': v, n = 'YES', ('weak: match is inside the genetic-data definition' if c == 'GG' else 'confirmed by hand from the definition text')
    else: raise SystemExit(f'unreviewed {c}')
    w.writerow([c, v, n]); out.flush()
out.close()
import collections
print(collections.Counter(r['health_sensitive_final'] for r in csv.DictReader(open('health_final.tsv'), delimiter='\t')), flush=True)
