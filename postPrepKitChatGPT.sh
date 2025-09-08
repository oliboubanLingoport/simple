#!/usr/bin/env bash

#
# From one PXML as an input file, create the translated pxml in French here
# This is just a big workaround, not a real way to do this
#
translate() {
 INPUT_FILE="$1"
 OUTPUT_FILE="$2"
 API_KEY="$API_KEY"

 echo "${API_KEY:0:4} ... ${API_KEY: -4}"


 # Start new XML file
 echo '<?xml version="1.0" encoding="utf-8"?>' > "$OUTPUT_FILE"
 echo '<resources>' >> "$OUTPUT_FILE"

 # Loop through <string> elements
 xmlstarlet sel -t -m "//string" \
  -v "@translate" -o "|" \
  -v "@segmentID" -o "|" \
  -v "@minLength" -o "|" \
  -v "@maxLength" -o "|" \
  -v "lrm_incontext" -o "|" \
  -v "llm_prompt" -o "|" \
  -v "SID" -o "|" \
  -v "normalize-space(value)" -n "$INPUT_FILE" | \
 while IFS="|" read -r TRANSLATE SEGMENT MIN MAX URL PROMPT SID VALUE; do
    # Clean URL
    URL=$(echo "$URL" | sed 's/&amp;/\&/g')

    # Call OpenAI API
    RESPONSE=$(curl -s https://api.openai.com/v1/chat/completions \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d "{
        \"model\": \"gpt-4o\",
        \"messages\": [
          {
            \"role\": \"user\",
            \"content\": [
              {
                \"type\": \"text\",
                \"text\": \"As a professional translator, using this image, only return the French translation for the string: '$VALUE'\"
              },
              {
                \"type\": \"image_url\",
                \"image_url\": { \"url\": \"$URL\" }
              }
            ]
          }
        ]
      }")

    # Extract translation (first choice message)
    TRANSLATION=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' | sed 's/^ *//;s/ *$//')

    echo "Translated segmentID=$SEGMENT → $TRANSLATION"

    # Write new <string> block into OUTPUT_FILE
    cat >> "$OUTPUT_FILE" <<EOF
  <string translate="$TRANSLATE" segmentID="$SEGMENT" minLength="$MIN" maxLength="$MAX">
    <lrm_incontext>$URL</lrm_incontext>
    <llm_prompt>$PROMPT</llm_prompt>
    <SID>$SID</SID>
    <value><![CDATA[$TRANSLATION]]></value>
  </string>
EOF
done

# Close root element
 echo '</resources>' >> "$OUTPUT_FILE"

}

#
# Go to the local directory where the zip file was created by the Prep Kit using LocalChatGPT connection
# unzip the files, 
# call the translate method above with an input and an output parameter
#
TO_TRANSLATION_DIR=/usr/local/tomcat/Lingoport_Data/CommandCenter/misc/to_chatgpt_local
FROM_TRANSLATION_DIR=/usr/local/tomcat/Lingoport_Data/CommandCenter/misc/from_chatgpt_local
TMP_DIR=/usr/local/tomcat/Lingoport_Data/CommandCenter/misc/tmp_translation
set -euo pipefail

# Ensure output directory exists
mkdir -p "$TO_TRANSLATION_DIR"
mkdir -p "$FROM_TRANSLATION_DIR"
mkdir -p "$TMP_DIR"

# Loop over all zip files in TO_DIR
for zipfile in "$TO_TRANSLATION_DIR"/*.zip; do
    [ -e "$zipfile" ] || continue  # skip if no zip files

    # Get the base filename without extension
    filename=$(basename "$zipfile" .zip)

    echo "Processing $filename.zip ..."

    # Create fresh temp directory for this zip
    workdir="$TMP_DIR/$filename"
    rm -rf "$workdir"
    mkdir -p "$workdir"

    # Unzip into workdir
    echo " zipfile=$zipfile"
    echo " workdir=$workdir"
    unzip -q "$zipfile" -d "$workdir"
    rm "$zipfile"

    # Find and translate each .pxml file
    find "$workdir" -type f -name "*.pxml" | while read -r pxml; do
       temp_file=$(mktemp)
       echo "  Translating: $pxml $temp_file"
       echo "  $pxml: "
       cat "$pxml"
       translate "$pxml"  "$temp_file"
       mv  "$temp_file" "$pxml"
    done

    # Re-zip preserving structure
    outzip="$FROM_TRANSLATION_DIR/$filename.zip"
    (cd "$workdir" && zip -qr "$outzip" .)

    echo "Created: $outzip"
done

# Cleanup temp files (optional)
rm -rf "$TMP_DIR"

echo "All done."


