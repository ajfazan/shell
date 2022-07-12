#!/bin/sh

fix_background() {

  BBOX=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".gpkg" XXXXXXXXXXXXXXXX)

  gdaltinex -q -f GPKG -lyr_name bbox ${BBOX} ${1}

  gdal_edit.py -unsetnodata ${1}

  SQL="MBRMinX( geom ) AS x1, MBRMinY( geom ) AS y1, MBRMaxX( geom ) AS x2, MBRMaxY( geom ) AS y2"
  SQL="SELECT ${SQL} FROM bbox"

  CSV=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".csv" XXXXXXXXXXXXXXXX)

  ogr2ogr -f CSV -sql "${SQL}" ${CSV} ${BBOX}

  sed -i '1d ; s/,/ /g' ${CSV}

  R_BAND=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  G_BAND=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  B_BAND=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)
  A_BAND=$(mktemp -q --tmpdir=${TMPDIR} --suffix=".tif" XXXXXXXXXXXXXXXX)

  KAPPA=0

  while IFS= read COLS ROWS; do

    let KAPPA+=1

  done < $(gdalinfo ${1} | egrep '^Size' | cut -d' ' -f3- | sed -r 's/,//g')

  while IFS= read XMIN YMIN XMAX YMAX; do

    let KAPPA+=1

  done < $(cat ${CSV})

  echo "[DEBUG]: ${KAPPA}"

  gdal_rasterize -q -of GTiff -ot Byte -burn 255 -l footprint -ts ${COLS} ${ROWS} \
    -te ${XMIN} ${YMIN} ${XMAX} ${YMAX} ${2} ${A_BAND}

  gdal_calc.py -A ${1} --A_band=1 -B ${A_BAND} --B_band=1 --type=Byte --format=GTiff --overwrite \
    --quiet --NoDataValue=0 --outfile=${R_BAND} --calc="( A * ( B != 0 ) ) + ( A == 0 ) * ( B != 0 )" &

  gdal_calc.py -A ${1} --A_band=2 -B ${A_BAND} --B_band=1 --type=Byte --format=GTiff --overwrite \
    --quiet --NoDataValue=0 --outfile=${G_BAND} --calc="( A * ( B != 0 ) ) + ( A == 0 ) * ( B != 0 )" &

  gdal_calc.py -A ${1} --A_band=3 -B ${A_BAND} --B_band=1 --type=Byte --format=GTiff --overwrite \
    --quiet --NoDataValue=0 --outfile=${B_BAND} --calc="( A * ( B != 0 ) ) + ( A == 0 ) * ( B != 0 )" &

  wait

  gdal_merge.py -q -o ${1} -ot Byte -of GTiff -n 0 -a_nodata 0 -separate \
    ${R_BAND} ${G_BAND} ${B_BAND}

  gdal_edit.py -colorinterp_1 red -colorinterp_2 green -colorinterp_3 blue ${1}

  rm -f ${R_BAND} ${G_BAND} ${B_BAND} ${A_BAND} ${BBOX} ${CSV}
}

if [ ! -d ${1} ]; then

  echo "First input argument must be a directory" 1>&2
  exit 1

fi

if [ ! -d ${2} ]; then

  echo "Second input argument must be a directory" 1>&2
  exit 1

fi

if [ ! -f ${3} ]; then

  echo "Third input argument must be a ZIP file" 1>&2
  exit 2

fi

DIR1=$(mktemp -q -d --tmpdir=$(realpath ${1}) XXXXXXXXXXXXXXXX)
DIR2=$(mktemp -q -d --tmpdir=$(realpath ${2}) XXXXXXXXXXXXXXXX)

unzip -q -j ${3} -d ${DIR1}

if [ ${?} -ne 0 ]; then

  echo "[ERROR] ZIP file '${3}' extraction failed" 1>&2
  exit 3

fi

for FILE in $(find ${DIR1} -type f -iname "*.tif"); do

  generate_raster_footprint --compress --nodata 0 ${FILE} ${DIR1}

  LAYER=$(basename ${FILE} | sed -r 's/^(.+)\.(.+)$/\1/')

  ENVELOPE1="${DIR1}/${LAYER}.gpkg"
  ENVELOPE2="${DIR2}/${LAYER}.gpkg"

  CSV="${DIR1}/${LAYER}.csv"

  ogrinfo -q -sql "ALTER TABLE '${LAYER}' RENAME TO footprint" ${ENVELOPE1}

  ogr2ogr -f CSV -lco SEPARATOR=SEMICOLON -sql "SELECT holes FROM footprint WHERE ( holes > 0 )" \
    ${CSV} ${ENVELOPE1}

  sed -i '1d' ${CSV}

  ogr2ogr -q -sql "SELECT ST_ExteriorRing( geom ) AS geom, source, 0 AS holes FROM footprint" \
    -nln footprint -nlt POLYGON ${ENVELOPE2} ${ENVELOPE1}

  if [ -z ${CSV} ]; then

    fix_background ${FILE} ${ENVELOPE2}

  fi

  gdal_translate -q -ot Byte -of JP2OpenJPEG -co QUALITY=100 -co REVERSIBLE=YES -co RESOLUTIONS=1 \
   -r bilinear -tr 0.5 0.5 -a_nodata 0 -stats ${FILE} "${DIR2}/${LAYER}.jp2"

done

cd ${DIR2}

TARGET=$(basename ${3})

zip -q -0 ${TARGET} *.jp2* && mv ${TARGET} ..

# rm -rf ${DIR1} ${DIR2}
