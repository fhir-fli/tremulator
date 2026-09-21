#!/usr/bin/env python3
"""Join the 195 UN member and observer states to GPD (encryption) and DLA Piper
(transfer, storage location, health as sensitive data). Country names differ
across sources; the alias maps below are explicit and the script fails if any
UN country is left unmatched in GPD. DLA gaps are written as 'unknown'.
Output: countries_195.tsv, one row per country, flushed per row."""
import csv, unicodedata, re, sys

def norm(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().lower()
    s = re.sub(r'[^a-z ]', ' ', s); s = re.sub(r'\b(the|of|and)\b', ' ', s)
    return ' '.join(s.split())

GPD_ALIAS = {
 'Bolivia (Plurinational State of)':'Bolivia','Brunei Darussalam':'Brunei','Cabo Verde':'Cape Verde',
 "China (the People's Republic of)":'China','Congo':'Republic of the Congo','Czechia':'Czech Republic',
 "Democratic People's Republic of Korea":'North Korea','Eswatini':'Swaziland','Gambia (Republic of The)':'Gambia',
 'Iran (Islamic Republic of)':'Iran','Lao People’s Democratic Republic':'Laos','Micronesia (Federated States of)':'Micronesia',
 'Naoero':'Nauru','Netherlands (Kingdom of the)':'Netherlands','North Macedonia':'Macedonia','Republic of Korea':'South Korea',
 'Republic of Moldova':'Moldova','Russian Federation':'Russia','Syrian Arab Republic':'Syria','Türkiye':'Turkey',
 'United Kingdom of Great Britain and Northern Ireland':'United Kingdom','United Republic of Tanzania':'Tanzania',
 'Venezuela, Bolivarian Republic of':'Venezuela','Viet Nam':'Vietnam','Holy See':'Vatican City','State of Palestine':'Palestine'}
DLA_ALIAS = {
 'Bolivia (Plurinational State of)':'Bolivia','Brunei Darussalam':'Brunei','Cabo Verde':'Cape Verde',
 "China (the People's Republic of)":'China','Congo':'Republic of Congo',"Côte D'Ivoire":'Côte d’Ivoire','Czechia':'Czech Republic',
 'Iran (Islamic Republic of)':'Iran','Lao People’s Democratic Republic':'Laos','Micronesia (Federated States of)':'Federated States of Micronesia',
 'Netherlands (Kingdom of the)':'Netherlands','Republic of Korea':'South Korea','Republic of Moldova':'Moldova',
 'Russian Federation':'Russia','Slovakia':'Slovak Republic','Türkiye':'Turkey','United Arab Emirates':'UAE - General',
 'United Kingdom of Great Britain and Northern Ireland':'United Kingdom','United Republic of Tanzania':'Tanzania',
 'United States of America':'United States','Venezuela, Bolivarian Republic of':'Venezuela','Viet Nam':'Vietnam'}

un = list(csv.DictReader(open('un195.tsv'), delimiter='\t'))
gpd = {norm(r['country']): r for r in csv.DictReader(open('gpd_encryption.tsv'), delimiter='\t')}
auto = {r['name']: r for r in csv.DictReader(open('dla_auto.tsv'), delimiter='\t')}
dla_by_norm = {norm(k): v for k, v in auto.items()}
rev = {r['code']: r for r in csv.DictReader(open('dla_reviewed.tsv'), delimiter='\t')}
loc = {r['code']: r for r in csv.DictReader(open('localisation_review.tsv'), delimiter='\t')}
hl = {r['code']: r for r in csv.DictReader(open('health_final.tsv'), delimiter='\t')}

cols = ['country','un_status','encryption_gpd','gpd_licensing','gpd_import_export','gpd_other',
        'dla_code','dla_last_modified','transfer','transfer_note','life_exception_in_dla',
        'storage_rule','storage_note','health_sensitive','health_note']
out = open('countries_195.tsv', 'w', newline='')
w = csv.writer(out, delimiter='\t'); w.writerow(cols); out.flush()
miss_g, miss_d = [], []
for u in un:
    name = u['country']
    g = gpd.get(norm(GPD_ALIAS.get(name, name)))
    if g is None: miss_g.append(name)
    d = dla_by_norm.get(norm(DLA_ALIAS.get(name, name)))
    if d is None: miss_d.append(name)
    code = d['code'] if d else ''
    row = [name, u['un_status'],
           g['assessment'] if g else 'unknown',
           (g or {}).get('Licensing/registration requirements', '')[:300],
           (g or {}).get('Import/export controls', '')[:300],
           (g or {}).get('Other restrictions', '')[:300],
           code, d['last_modified'] if d else '',
           rev[code]['transfer_final'] if d else 'unknown', rev[code]['review_note'] if d else 'not covered by DLA Piper',
           rev[code]['vital_final'] if d else 'unknown',
           loc[code]['storage_rule'] if d else 'unknown', loc[code]['note'] if d else 'not covered by DLA Piper',
           hl[code]['health_sensitive_final'] if d else 'unknown', hl[code]['note'] if d else 'not covered by DLA Piper']
    w.writerow(row); out.flush()
out.close()
print(f'rows {len(un)}; unmatched in GPD {len(miss_g)} {miss_g}; not covered by DLA {len(miss_d)}', flush=True)
print('not covered by DLA:', miss_d, flush=True)
if miss_g: sys.exit(1)
