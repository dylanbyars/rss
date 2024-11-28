#!/bin/bash

# Replace these variables with your actual credentials
USERNAME="dylan"
PASSWORD="fUULayh7T6c*9z" # Replace with your FreshRSS password
BASE_URL="http://localhost/api/greader.php"

# Number of articles to present for selection
NUM_ARTICLES=20  # Set to the desired number of articles to present
TIMEFRAME_HOURS=50  # Adjust as needed

# Check if required commands are installed
for cmd in pandoc jq gum awk sort head; do
    if ! command -v $cmd &> /dev/null
    then
        echo "$cmd is required but it's not installed. Please install $cmd and try again."
        exit 1
    fi
done

# Step 1: Obtain the Auth Token
AUTH_RESPONSE=$(curl -s -X POST "$BASE_URL/accounts/ClientLogin" \
    -d "Email=$USERNAME" \
    -d "Passwd=$PASSWORD")

AUTH_TOKEN=$(echo "$AUTH_RESPONSE" | grep '^Auth=' | cut -d '=' -f 2)

if [ -z "$AUTH_TOKEN" ]; then
    echo "Failed to obtain Auth Token. Please check your credentials."
    exit 1
fi

# Step 2: Get the Category ID for "Youtube"
CATEGORY_LIST=$(curl -s -H "Authorization:GoogleLogin auth=$AUTH_TOKEN" \
  "$BASE_URL/reader/api/0/tag/list?output=json")

# Extract the category ID for "Youtube"
YOUTUBE_CATEGORY_ID=$(echo "$CATEGORY_LIST" | jq -r '.tags[] | select(.id | endswith("YouTube")) | .id')

if [ -z "$YOUTUBE_CATEGORY_ID" ]; then
    echo "Could not find the category ID for 'Youtube'."
    exit 1
fi

# Step 3: Calculate the timestamp for the past n hours in microseconds
CURRENT_TIMESTAMP=$(date +%s)
TIMEFRAME_SECONDS=$((TIMEFRAME_HOURS * 3600))
TIMESTAMP_N_HOURS_AGO=$((CURRENT_TIMESTAMP - TIMEFRAME_SECONDS))
TIMESTAMP_MICROSECONDS=$((TIMESTAMP_N_HOURS_AGO * 1000000))

# Step 4: Fetch article IDs and titles, excluding "Youtube" category
ARTICLES_METADATA=$(curl -s -H "Authorization: GoogleLogin auth=$AUTH_TOKEN" \
  "$BASE_URL/reader/api/0/stream/contents/user/-/state/com.google/reading-list?output=json&n=1000&nt=$TIMESTAMP_MICROSECONDS")

# Extract IDs and titles, filtering out articles from "Youtube" category
ARTICLES_LIST=$(echo "$ARTICLES_METADATA" | jq -c --arg yt_cat "$YOUTUBE_CATEGORY_ID" \
  '.items[] | select(.categories | index($yt_cat) | not) | {id: .id, title: .title}')

# Check if any articles were found
NUM_AVAILABLE_ARTICLES=$(echo "$ARTICLES_LIST" | wc -l)
if [ "$NUM_AVAILABLE_ARTICLES" -eq 0 ]; then
    echo "No articles found in the past $TIMEFRAME_HOURS hours excluding 'Youtube' category."
    exit 1
fi

# Randomly select up to NUM_ARTICLES articles
if [ "$NUM_AVAILABLE_ARTICLES" -le "$NUM_ARTICLES" ]; then
    SELECTED_ARTICLES="$ARTICLES_LIST"
else
    # Randomly shuffle and select NUM_ARTICLES articles
    SELECTED_ARTICLES=$(echo "$ARTICLES_LIST" | awk 'BEGIN {srand()} {print rand() "\t" $0}' | sort -k1,1n | cut -f2- | head -n "$NUM_ARTICLES")
fi

# Prepare the options for gum
declare -a GUM_CHOICES
declare -a ARTICLES_IDS
INDEX=0
while read -r article; do
    TITLE=$(echo "$article" | jq -r '.title')
    ID=$(echo "$article" | jq -r '.id')
    # Escape any double quotes in the title
    TITLE_ESCAPED=$(echo "$TITLE" | sed 's/"/\\"/g')
    GUM_CHOICES[$INDEX]="$INDEX) $TITLE_ESCAPED"
    ARTICLES_IDS[$INDEX]=$ID
    INDEX=$((INDEX + 1))
done <<< "$SELECTED_ARTICLES"

# Use gum to present the multiselect list
SELECTED_ITEMS=$(printf '%s\n' "${GUM_CHOICES[@]}" | gum choose --no-limit)

# Check if the user made any selection
if [ -z "$SELECTED_ITEMS" ]; then
    echo "No articles selected."
    exit 0
fi

# Extract selected indices
SELECTED_INDICES=()
for item in $SELECTED_ITEMS; do
    # Extract the index from the selected item (format: "index) title")
    INDEX_SELECTED=$(echo "$item" | cut -d')' -f1)
    SELECTED_INDICES+=($INDEX_SELECTED)
done

# Prepare POST data for fetching selected articles
POST_DATA=""
for index in "${SELECTED_INDICES[@]}"; do
    ID=${ARTICLES_IDS[$index]}
    POST_DATA+="i=$ID&"
done
POST_DATA=${POST_DATA%&}

# Step 5: Fetch full content of selected articles
FULL_ARTICLES_JSON=$(curl -s -H "Authorization: GoogleLogin auth=$AUTH_TOKEN" \
    -d "$POST_DATA" \
    "$BASE_URL/reader/api/0/stream/items/contents?output=json")

# Check if articles were fetched successfully
if [ -z "$FULL_ARTICLES_JSON" ]; then
    echo "Failed to fetch full articles."
    exit 1
fi

# Create a temporary file to store processed articles
PROCESSED_ARTICLES_FILE=$(mktemp)

# Process the articles
echo "$FULL_ARTICLES_JSON" | jq -c '.items[]' | while read -r article; do
    TITLE=$(echo "$article" | jq -r '.title // "No Title"')
    URL=$(echo "$article" | jq -r '.alternate[0].href // ""')
    CONTENT_HTML=$(echo "$article" | jq -r '.content.content // .summary.content // ""')

    # Convert HTML to Markdown without unwanted noise
    CONTENT_MD=$(echo "$CONTENT_HTML" | pandoc --from=html --to=markdown-native_divs-native_spans-raw_attribute)

    # Combine into final format and append to the file
    printf "Title: %s\nURL: %s\nContent:\n%s\n\n" "$TITLE" "$URL" "$CONTENT_MD" >> "$PROCESSED_ARTICLES_FILE"
done

# Continue with the rest of your script (e.g., send to LLM)

# For demonstration, output the processed articles
cat "$PROCESSED_ARTICLES_FILE"

# Clean up temporary file
rm "$PROCESSED_ARTICLES_FILE"

