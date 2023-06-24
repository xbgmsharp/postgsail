---------------------------------------------------------------------------
-- https://www.naturalearthdata.com
--
-- https://naciscdn.org/naturalearth/10m/physical/ne_10m_geography_marine_polys.zip
--
-- https://github.com/nvkelso/natural-earth-vector/raw/master/10m_physical/ne_10m_geography_marine_polys.shp
--

-- Import from shapefile
-- # shp2pgsql ne_10m_geography_marine_polys.shp public.ne_10m_geography_marine_polys | psql -U ${POSTGRES_USER} signalk
--
-- PostgSail Customization, add tropics area.

-- List current database
select current_database();

-- connect to the DB
\c signalk

CREATE TABLE public.ne_10m_geography_marine_polys (
	gid serial4 NOT NULL,
	featurecla TEXT NULL,
	"name" TEXT NULL,
	namealt TEXT NULL,
	changed TEXT NULL,
	note TEXT NULL,
	name_fr TEXT NULL,
	min_label float8 NULL,
	max_label float8 NULL,
	scalerank int2 NULL,
	"label" TEXT NULL,
	wikidataid TEXT NULL,
	name_ar TEXT NULL,
	name_bn TEXT NULL,
	name_de TEXT NULL,
	name_en TEXT NULL,
	name_es TEXT NULL,
	name_el TEXT NULL,
	name_hi TEXT NULL,
	name_hu TEXT NULL,
	name_id TEXT NULL,
	name_it TEXT NULL,
	name_ja TEXT NULL,
	name_ko TEXT NULL,
	name_nl TEXT NULL,
	name_pl TEXT NULL,
	name_pt TEXT NULL,
	name_ru TEXT NULL,
	name_sv TEXT NULL,
	name_tr TEXT NULL,
	name_vi TEXT NULL,
	name_zh TEXT NULL,
	ne_id int8 NULL,
	name_fa TEXT NULL,
	name_he TEXT NULL,
	name_uk TEXT NULL,
	name_ur TEXT NULL,
	name_zht TEXT NULL,
	geom geometry(multipolygon,4326) NULL,
	CONSTRAINT ne_10m_geography_marine_polys_pkey PRIMARY KEY (gid)
);
-- Add GIST index
CREATE INDEX ne_10m_geography_marine_polys_geom_idx
  ON public.ne_10m_geography_marine_polys
  USING GIST (geom);

-- Description
COMMENT ON TABLE
    public.ne_10m_geography_marine_polys
    IS 'imperfect but light weight geographic marine areas from https://www.naturalearthdata.com';

-- Import data
COPY public.ne_10m_geography_marine_polys(gid,featurecla,"name",namealt,changed,note,name_fr,min_label,max_label,scalerank,"label",wikidataid,name_ar,name_bn,name_de,name_en,name_es,name_el,name_hi,name_hu,name_id,name_it,name_ja,name_ko,name_nl,name_pl,name_pt,name_ru,name_sv,name_tr,name_vi,name_zh,ne_id,name_fa,name_he,name_uk,name_ur,name_zht,geom)
FROM '/docker-entrypoint-initdb.d/ne_10m_geography_marine_polys.csv'
DELIMITER ','
CSV HEADER;
