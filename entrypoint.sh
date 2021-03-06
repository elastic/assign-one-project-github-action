#!/bin/sh -l

PROJECT_URL="$INPUT_PROJECT"
if [ -z "$PROJECT_URL" ]; then
  echo "PROJECT_URL is not defined." >&2
  exit 1
fi

get_project_type() {
  _PROJECT_URL="$1"

  case "$_PROJECT_URL" in
    https://github.com/orgs/*)
      echo "org"
      ;;
    https://github.com/users/*)
      echo "user"
      ;;
    https://github.com/*/projects/*)
      echo "repo"
      ;;
    *)
      echo "Invalid PROJECT_URL: $_PROJECT_URL" >&2
      exit 1
      ;;
  esac

  unset _PROJECT_URL
}

find_column_id() {
  _PROJECT_ID="$1"
  _INITIAL_COLUMN_NAME="$2"

  _COLUMNS=$(curl -s -X GET -u "$GITHUB_ACTOR:$TOKEN" --retry 3 \
          -H 'Accept: application/vnd.github.inertia-preview+json' \
          "https://api.github.com/projects/$_PROJECT_ID/columns")


  echo "$_COLUMNS" | jq -r ".[] | select(.name == \"$_INITIAL_COLUMN_NAME\").id"
  unset _PROJECT_ID _INITIAL_COLUMN_NAME _COLUMNS
}

PROJECT_TYPE=$(get_project_type "${PROJECT_URL:?<Error> required this environment variable}")

if [ "$PROJECT_TYPE" = org ] || [ "$PROJECT_TYPE" = user ]; then
  if [ -z "$MY_GITHUB_TOKEN" ]; then
    echo "MY_GITHUB_TOKEN not defined" >&2
    exit 1
  fi

  TOKEN="$MY_GITHUB_TOKEN" # It's User's personal access token. It should be secret.
else
  if [ -z "$GITHUB_TOKEN" ]; then
    echo "GITHUB_TOKEN not defined" >&2
    exit 1
  fi

  TOKEN="$GITHUB_TOKEN"    # GitHub sets. The scope in only the repository containing the workflow file.
fi

INITIAL_COLUMN_NAME="$INPUT_COLUMN_NAME"
if [ -z "$INITIAL_COLUMN_NAME" ]; then
  # assing the column name by default
  INITIAL_COLUMN_NAME='To do'
  if [ "$GITHUB_EVENT_NAME" == "pull_request" ]; then
    echo "changing col name for PR event"
    INITIAL_COLUMN_NAME='In progress'
  fi
fi


PROJECT_ID="$INPUT_PROJECT_ID"
INITIAL_COLUMN_ID=$(find_column_id "$PROJECT_ID" "${INITIAL_COLUMN_NAME:?<Error> required this environment variable}")

if [ -z "$INITIAL_COLUMN_ID" ]; then
  echo "INITIAL_COLUMN_ID is not found." >&2
  exit 1
fi

case "$GITHUB_EVENT_NAME" in
  issues)
    ISSUE_ID=$(jq -r '.issue.id' < "$GITHUB_EVENT_PATH")

    # Add this issue to the project column
    curl -s -X POST -u "$GITHUB_ACTOR:$TOKEN" --retry 3 \
     -H 'Accept: application/vnd.github.inertia-preview+json' \
     -d "{\"content_type\": \"Issue\", \"content_id\": $ISSUE_ID}" \
     "https://api.github.com/projects/columns/$INITIAL_COLUMN_ID/cards"

     echo "Added issue to project" >&2
    ;;
  pull_request|pull_request_target)
    PULL_REQUEST_ID=$(jq -r '.pull_request.id' < "$GITHUB_EVENT_PATH")

    # Add this pull_request to the project column
    curl -s -X POST -u "$GITHUB_ACTOR:$TOKEN" --retry 3 \
     -H 'Accept: application/vnd.github.inertia-preview+json' \
     -d "{\"content_type\": \"PullRequest\", \"content_id\": $PULL_REQUEST_ID}" \
     "https://api.github.com/projects/columns/$INITIAL_COLUMN_ID/cards"

    echo "Added pull request to project" >&2
    ;;
  *)
    echo "Nothing to be done on this action: $GITHUB_EVENT_NAME" >&2
    exit 1
    ;;
esac
