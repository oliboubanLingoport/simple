#!/usr/bin/env bash

#
# From one PXML as an input file, create the translated pxml in French here
# This is just a big workaround, not a real way to do this
#
translate() {
 INPUT_FILE="$1"
 OUTPUT_FILE="$2"
 API_KEY="$API_KEY"

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

# unzip and place the files in the top to_translation directory to be ready to call 'translate' above
unzip *.zip
find . -name "*.pxml" -exec mv {} "$TO_TRANSLATION_DIR" \;

cd "$TO_TRANSLATION_DIR"
for INPUT_FILE in *; do
  if [ -f "$INPUT_FILE" ]; then
          OUTPUT_FILE=" ${FROM_TRANSLATION_DIR}/${INPUT_FILE}"
          echo "Translation ${INPUT_FILE} -> ${OUTPUT_FILE}"
  fi
done

