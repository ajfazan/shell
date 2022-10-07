#!/bin/sh

. "$(dirname $(realpath ${0}))/functions.sh"

if [ ${#} -ne 2 ]; then

  printf "Usage:\n\t%s <RGB_TIFF_FILE> <OUT_DIR>\n\n" $(basename ${0})
  exit 4

fi

if [ ! -f ${1} ]; then

  echo "First input argument must be a file"
  exit 1

fi

if [ ! -d ${2} ]; then

  echo "Second input argument must be a directory"
  exit 2

fi

fix_rgb_background $(realpath ${1}) $(realpath ${2})
