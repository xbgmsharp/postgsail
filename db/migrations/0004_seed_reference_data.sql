-- +goose Up

-- Seed stays types
INSERT INTO api.stays_at(stay_code, description) VALUES
    (1, 'Unknown'),
    (2, 'Anchor'),
    (3, 'Mooring Buoy'),
    (4, 'Dock')
ON CONFLICT (stay_code) DO NOTHING;

-- Seed geocoders
INSERT INTO public.geocoders (name, url, reverse_url) VALUES
    ('nominatim', 'https://nominatim.openstreetmap.org', 'https://nominatim.openstreetmap.org/reverse'),
    ('OpenCage', 'https://api.opencagedata.com/geocode/v1', 'https://api.opencagedata.com/geocode/v1'),
    ('Mapbox', 'https://api.mapbox.com/geocoding/v5', 'https://api.mapbox.com/geocoding/v5')
ON CONFLICT (name) DO NOTHING;

-- Load MID data from CSV
COPY public.email_templates (name, email_subject, email_content, pushover_title, pushover_message)
FROM '/db/seed_data/email_templates.csv'
DELIMITER ','
CSV HEADER;

-- Load MID data from CSV
COPY public.badges (name, description)
FROM '/db/seed_data/badges.csv'
DELIMITER ','
CSV HEADER;

-- Load MID data from CSV
COPY public.mid (country, id, country_id)
FROM '/db/seed_data/mid.csv'
DELIMITER ','
CSV HEADER;

-- Load ISO3166 from CSV
COPY public.iso3166 (id, country, alpha_2, alpha_3)
FROM '/db/seed_data/iso3166.csv'
DELIMITER ','
CSV HEADER;

-- Load AIS types from CSV
COPY public.aistypes (id, description)
FROM '/db/seed_data/aistypes.csv'
DELIMITER ','
CSV HEADER;

-- Load Natural Earth marine polygons from CSV
COPY public.ne_10m_geography_marine_polys(gid,featurecla,"name",namealt,changed,note,name_fr,min_label,max_label,scalerank,"label",wikidataid,name_ar,name_bn,name_de,name_en,name_es,name_el,name_hi,name_hu,name_id,name_it,name_ja,name_ko,name_nl,name_pl,name_pt,name_ru,name_sv,name_tr,name_vi,name_zh,ne_id,name_fa,name_he,name_uk,name_ur,name_zht,geom)
FROM '/db/seed_data/ne_10m_geography_marine_polys.csv'
DELIMITER ','
CSV HEADER;

-- +goose Down
-- Clean up seed data
DELETE FROM public.geocoders;
DELETE FROM public.email_templates;
DELETE FROM public.bagdes;
DELETE FROM public.mid;
DELETE FROM public.iso3166;
DELETE FROM public.aistypes;
DELETE FROM public.ne_10m_geography_marine_polys;