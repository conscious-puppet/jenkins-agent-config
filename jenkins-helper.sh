#!/bin/bash

# Jenkins Build Progress Monitor & Trigger
# Usage: 
#   Monitor: ./jenkins-helper.sh <branch-name> [build-number]
#   Trigger: ./jenkins-helper.sh trigger <branch-name>
#   List branches: ./jenkins-helper.sh list
#
# Environment: JENKINS_DEV_URL, JENKINS_DEV_USER, JENKINS_DEV_TOKEN
# 
# JENKINS_DEV_URL should be in format: https://jenkins.example.com/job/<job-name>
# Example: export JENKINS_DEV_URL="https://jenkins.example.com/job/your-job-name"

set -e

# Configuration from environment
JENKINS_DEV_URL="${JENKINS_DEV_URL:-}"
JENKINS_DEV_USER="${JENKINS_DEV_USER:-}"
JENKINS_DEV_TOKEN="${JENKINS_DEV_TOKEN:-}"

COMMAND="${1:-}"
BRANCH_NAME="${2:-}"
BUILD_NUMBER="${3:-}"

# Helper function to show usage
show_usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  monitor <branch-name> [build-number]  Monitor build progress"
    echo "  trigger <branch-name>                 Trigger a new build"
    echo "  list                                  List all branches"
    echo ""
    echo "Environment Variables:"
    echo "  JENKINS_DEV_URL    - Jenkins URL (e.g., https://jenkins.example.com/job/your-job)"
    echo "  JENKINS_DEV_USER   - Jenkins username"
    echo "  JENKINS_DEV_TOKEN  - Jenkins API token"
    echo ""
    echo "Examples:"
    echo "  $0 monitor your-branch-name"
    echo "  $0 monitor your-branch-name 42"
    echo "  $0 trigger your-branch-name"
    echo "  $0 list"
    echo ""
    echo "Note: You can also run without command for monitor mode:"
    echo "  $0 <branch-name> [build-number]"
}

# Check required environment variables
check_env() {
    if [[ -z "$JENKINS_DEV_URL" || -z "$JENKINS_DEV_USER" || -z "$JENKINS_DEV_TOKEN" ]]; then
        echo "Error: Set JENKINS_DEV_URL, JENKINS_DEV_USER, JENKINS_DEV_TOKEN environment variables"
        echo ""
        show_usage
        exit 1
    fi
}

# URL encode the branch name for API calls
encode_branch() {
    echo "$1" | sed 's/ /%20/g' | sed 's/\//%2F/g'
}

# Command: list branches
cmd_list() {
    check_env
    
    echo "Fetching branches..."
    echo ""
    
    # Get branches from multibranch pipeline
    BRANCHES_JSON=$(curl -s -u "$JENKINS_DEV_USER:$JENKINS_DEV_TOKEN" \
        "$JENKINS_DEV_URL/api/json?tree=jobs[name,lastBuild[number,result,building,timestamp]]" 2>/dev/null)
    
    if [[ -z "$BRANCHES_JSON" ]]; then
        echo "Error: Could not fetch branches from $JENKINS_DEV_URL"
        exit 1
    fi
    
    echo "Branches:"
    echo "=============================================="
    
    echo "$BRANCHES_JSON" | python3 -c "
import sys, json

try:
    data = json.load(sys.stdin)
    jobs = data.get('jobs', [])
    
    # Filter for branches (typically have some naming pattern)
    branches = []
    for job in jobs:
        name = job.get('name', '')
        last_build = job.get('lastBuild', {})
        
        if last_build:
            building = '🔄' if last_build.get('building') else '  '
            result = last_build.get('result', 'PENDING')
            number = last_build.get('number', '')
            
            # Colorize results
            if result == 'SUCCESS':
                result_str = '✅ SUCCESS'
            elif result == 'FAILURE':
                result_str = '❌ FAILURE'
            elif result == 'UNSTABLE':
                result_str = '⚠️  UNSTABLE'
            elif result == 'ABORTED':
                result_str = '⏹️  ABORTED'
            else:
                result_str = '⏳ ' + result
            
            print(f'{building} {name:50s} #{number:5s} {result_str}')
        else:
            print(f'  {name:50s} (no builds)')
    
except Exception as e:
    print(f'Error parsing response: {e}')
" 2>/dev/null || echo "Error parsing branches"
}

# Command: trigger build
cmd_trigger() {
    check_env
    
    if [[ -z "$BRANCH_NAME" ]]; then
        echo "Error: Branch name required for trigger"
        echo "Usage: $0 trigger <branch-name>"
        exit 1
    fi
    
    ENCODED_BRANCH=$(encode_branch "$BRANCH_NAME")
    TRIGGER_URL="$JENKINS_DEV_URL/job/$ENCODED_BRANCH/build"
    
    echo "Triggering build for branch: $BRANCH_NAME"
    echo "URL: $TRIGGER_URL"
    echo ""
    
    # Trigger the build
    RESPONSE=$(curl -s -w "%{http_code}" -o /dev/null -X POST \
        -u "$JENKINS_DEV_USER:$JENKINS_DEV_TOKEN" \
        "$TRIGGER_URL")
    
    if [[ "$RESPONSE" == "201" || "$RESPONSE" == "200" ]]; then
        echo "✅ Build triggered successfully!"
        
        # Wait a moment and get the queue location
        sleep 2
        
        # Get the latest build number
        BUILD_INFO=$(curl -s -u "$JENKINS_DEV_USER:$JENKINS_DEV_TOKEN" \
            "$JENKINS_DEV_URL/job/$ENCODED_BRANCH/api/json")
        
        QUEUE_ID=$(echo "$BUILD_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('queueId',''))" 2>/dev/null || echo "")
        LAST_BUILD=$(echo "$BUILD_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('lastBuild',{}).get('number',''))" 2>/dev/null || echo "")
        
        if [[ -n "$LAST_BUILD" ]]; then
            echo "Queue ID: $QUEUE_ID"
            echo "Build URL: $JENKINS_DEV_URL/job/$ENCODED_BRANCH/$LAST_BUILD/"
            echo ""
            read -p "Monitor this build? [Y/n] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                cmd_monitor "$BRANCH_NAME" "$LAST_BUILD"
            fi
        fi
    elif [[ "$RESPONSE" == "404" ]]; then
        echo "❌ Branch '$BRANCH_NAME' not found"
        exit 1
    else
        echo "❌ Failed to trigger build (HTTP $RESPONSE)"
        exit 1
    fi
}

# Command: monitor build
cmd_monitor() {
    check_env
    
    # If called without explicit command, handle the old format
    if [[ -z "$COMMAND" && -n "$BRANCH_NAME" ]]; then
        # This is monitor mode with just branch name
        BUILD_NUMBER="$BRANCH_NAME"
        BRANCH_NAME="$COMMAND"
        COMMAND="monitor"
    fi
    
    if [[ -z "$BRANCH_NAME" ]]; then
        echo "Error: Branch name required"
        echo "Usage: $0 monitor <branch-name> [build-number]"
        exit 1
    fi
    
    ENCODED_BRANCH=$(encode_branch "$BRANCH_NAME")
    
    # Get latest build number if not specified
    if [[ -z "$BUILD_NUMBER" ]]; then
        echo "Fetching latest build for $BRANCH_NAME..."
        BUILD_INFO=$(curl -s -u "$JENKINS_DEV_USER:$JENKINS_DEV_TOKEN" \
            "$JENKINS_DEV_URL/job/$ENCODED_BRANCH/api/json" 2>/dev/null)
        
        if [[ -z "$BUILD_INFO" ]]; then
            echo "Error: Could not find branch '$BRANCH_NAME'"
            exit 1
        fi
        
        BUILD_NUMBER=$(echo "$BUILD_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('lastBuild',{}).get('number',''))" 2>/dev/null || echo "")
        
        if [[ -z "$BUILD_NUMBER" ]]; then
            echo "Error: Could not determine latest build number for branch '$BRANCH_NAME'"
            echo "Tip: Use '$0 trigger $BRANCH_NAME' to start a new build"
            exit 1
        fi
    fi
    
    # Get build info
    BUILD_API_URL="$JENKINS_DEV_URL/job/$ENCODED_BRANCH/$BUILD_NUMBER/api/json"
    BUILD_INFO=$(curl -s -u "$JENKINS_DEV_USER:$JENKINS_DEV_TOKEN" "$BUILD_API_URL")
    
    if [[ -z "$BUILD_INFO" ]]; then
        echo "Error: Could not fetch build info for $BRANCH_NAME #$BUILD_NUMBER"
        exit 1
    fi
    
    # Parse build details
    RESULT=$(echo "$BUILD_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result','IN_PROGRESS'))" 2>/dev/null || echo "UNKNOWN")
    BUILD_STATUS=$(echo "$BUILD_INFO" | python3 -c "import sys,json; d=json.load(sys.stdin); print('Building' if d.get('building') else d.get('result','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
    DURATION=$(echo "$BUILD_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('duration',0))" 2>/dev/null || echo "0")
    TIMESTAMP=$(echo "$BUILD_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('timestamp',0))" 2>/dev/null || echo "0")
    
    # Convert duration to human readable
    if [[ "$DURATION" -gt 0 ]]; then
        SECONDS=$((DURATION / 1000))
        DURATION_HUMAN=$(date -d "@$SECONDS" -u +%H:%M:%S 2>/dev/null || echo "${SECONDS}s")
    else
        DURATION_HUMAN="0s"
    fi
    
    # Calculate elapsed time
    if [[ "$TIMESTAMP" -gt 0 ]]; then
        STARTED_AT=$((TIMESTAMP / 1000))
        ELAPSED=$(($(date +%s) - STARTED_AT))
        ELAPSED_HUMAN=$(date -d "@$ELAPSED" -u +%H:%M:%S 2>/dev/null || echo "${ELAPSED}s")
    fi
    
    # Get estimated duration based on progress
    ESTIMATED_DURATION=$(echo "$BUILD_INFO" | python3 -c "import sys,json; print(json.load(sys.stdin).get('estimatedDuration',0))" 2>/dev/null || echo "0")
    if [[ "$ESTIMATED_DURATION" -gt 0 && "$BUILD_STATUS" == "Building" ]]; then
        EST_SECONDS=$((ESTIMATED_DURATION / 1000))
        EST_HUMAN=$(date -d "@$EST_SECONDS" -u +%H:%M:%S 2>/dev/null || echo "${EST_SECONDS}s")
        PROGRESS=$(echo "scale=1; $ELAPSED * 100 / $ESTIMATED_DURATION" | bc 2>/dev/null || echo "?")
        PROGRESS_INFO=" (${PROGRESS}% of estimated ${EST_HUMAN})"
    else
        PROGRESS_INFO=""
    fi
    
    # Display header
    echo ""
    echo "=============================================="
    echo "  Build Progress: $BRANCH_NAME #$BUILD_NUMBER"
    echo "=============================================="
    echo ""
    
    # Status
    if [[ "$BUILD_STATUS" == "Building" ]]; then
        echo "Status:    Building (elapsed: $ELAPSED_HUMAN${PROGRESS_INFO})"
    else
        echo "Status:    $RESULT (duration: $DURATION_HUMAN)"
    fi
    
    BUILD_URL="$JENKINS_DEV_URL/job/$ENCODED_BRANCH/$BUILD_NUMBER/"
    echo "URL:       $BUILD_URL"
    echo ""
    
    # Get pipeline stages (for Pipeline jobs)
    echo "Stages:"
    echo "----------------------------------------------"
    STAGES_OUTPUT=$(echo "$BUILD_INFO" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    # Check for Pipeline stages
    if '_class' in data and 'WorkflowRun' in data['_class']:
        stages = data.get('stageDurations', {})
        if stages:
            # Get stage status from different field
            for stage_name, duration in stages.items():
                print(f'  • {stage_name}')
        else:
            # Fallback to stages array
            stages = data.get('stages', [])
            if stages:
                for stage in stages:
                    status = stage.get('status', 'UNKNOWN')
                    name = stage.get('name', 'Unnamed')
                    print(f'  • {name}: {status}')
            else:
                print('  (No stages data available)')
    else:
        print('  (Not a pipeline job)')
except Exception as e:
    print(f'  (Error parsing stages: {e})')
" 2>/dev/null)
    
    if [[ -n "$STAGES_OUTPUT" ]]; then
        echo "$STAGES_OUTPUT"
    else
        echo "  (No stages data available)"
    fi
    echo ""
    
    # Get current executing stage from console or API
    echo "Current Stage:"
    CURRENT_EXEC=$(echo "$BUILD_INFO" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if '_class' in data:
        # Try to get current stages
        stages = data.get('currentStages', [])
        if stages:
            for s in stages:
                print(f'  • {s.get(\"name\", \"Unknown\")} (running)')
        else:
            print('  (No active stage)')
    else:
        print('  (No stage data)')
except:
    print('  (No active stage)')
" 2>/dev/null)
    echo "$CURRENT_EXEC"
    echo ""
    
    # Get console log (last 30 lines)
    echo "Recent Console Output:"
    echo "----------------------------------------------"
    CONSOLE_URL="$JENKINS_DEV_URL/job/$ENCODED_BRANCH/$BUILD_NUMBER/consoleText"
    curl -s -u "$JENKINS_DEV_USER:$JENKINS_DEV_TOKEN" "$CONSOLE_URL" | tail -n 30
    echo "----------------------------------------------"
    echo ""
    
    # Poll for updates if still building
    if [[ "$BUILD_STATUS" == "Building" ]]; then
        echo "Polling for updates every 30 seconds (Ctrl+C to stop)..."
        while true; do
            sleep 30
            echo ""
            echo "=== Updated at $(date) ==="
            # Recall this function with current args
            cmd_monitor "$BRANCH_NAME" "$BUILD_NUMBER"
        done
    fi
}

# Main dispatch
case "$COMMAND" in
    list|ls)
        cmd_list
        ;;
    trigger)
        cmd_trigger
        ;;
    monitor|"")
        # If no command, treat as monitor mode
        if [[ -n "$BRANCH_NAME" ]]; then
            cmd_monitor
        else
            show_usage
            exit 1
        fi
        ;;
    help|-h|--help)
        show_usage
        ;;
    *)
        # Assume it's monitor mode with branch name as first arg
        if [[ -n "$COMMAND" ]]; then
            BRANCH_NAME="$COMMAND"
            BUILD_NUMBER="$BRANCH_NAME"
            cmd_monitor
        else
            show_usage
            exit 1
        fi
        ;;
esac
