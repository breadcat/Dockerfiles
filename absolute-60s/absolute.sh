#!/bin/bash

while true
do
  pageuri=https://absoluteradio.co.uk/60s/music/ # webpage variable
  outfile=/pub/absolute-60s.txt # output file
  pagesource=$(wget "$pageuri" -qO-) # grab base file as variable
  artists=$(printf "$pagesource" | grep song-artist\" | sed 's/^.*>\([^<]*\)<.*$/\1/') # artists variable
  titles=$(printf "$pagesource" | grep song-title | cut -d\> -f3 | cut -d\< -f1) # titles variable
  paste <(printf "$artists") <(printf "$titles") | sed -e 's/\t/ - /g' >> "$outfile" # merge line by line
  sed -i -e 's/^The /\t/' "$outfile" # replace articles
  sort -b -u -o "$outfile" "$outfile" # sort and de-dupe output
  sed -i -e 's/^\t/The /' "$outfile" # revert articles
  printf "Script run on $(date)\n"
  sleep 900 # sleep for 15 miutes
done