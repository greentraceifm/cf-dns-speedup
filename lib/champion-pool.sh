# Champion pool update and reporting helpers.
# This file is sourced by cf-dns-speedup.sh.

update_champion_pool() {
  [ "${CFST_CHAMPION_POOL:-0}" = "1" ] || return 0
  if [ "${CFST_EXTERNAL_CANDIDATES:-0}" = "1" ] && [ "${CFST_EXTERNAL_CANDIDATES_ALLOW_CHAMPION:-0}" != "1" ]; then
    log "冠军池：外部候选源实验默认不写入冠军池"
    return 0
  fi
  [ -s "$STABILITY_RESULT_FILE" ] || return 0
  local tmp old now
  tmp="$APP_DIR/champion-pool.tmp"
  old="$APP_DIR/champion-pool.old.tsv"
  now="$(date '+%F %T')"
  [ -s "$CHAMPION_POOL_FILE" ] && cp "$CHAMPION_POOL_FILE" "$old" || printf 'ip\tbest_min_speed\tbest_avg_speed\trecent_min_speed\tfail_count\tfirst_seen\tlast_seen\tsource\thealth_status\tstable_score\trecent_low_count\tpool_type\tlifecycle_state\tlifecycle_reason\tobservation_count\tconsecutive_passes\tconsecutive_lows\tpromotion_ready\n' > "$old"
  [ -s "$CHAMPION_LIFECYCLE_AUDIT_FILE" ] || printf 'observed_at\tip\taction\thealth_status\tfail_count\tstable_score\tlifecycle_reason\n' > "$CHAMPION_LIFECYCLE_AUDIT_FILE"
  awk -F '\t' -v now="$now" -v degrade="${CFST_DEGRADE_MIN_SPEED:-2}" -v champion_fail="${CFST_CHAMPION_FAIL_MIN_SPEED:-8}" -v rounds="${CFST_STABILITY_TEST_ROUNDS:-0}" -v evict="${CFST_FAIL_EVICT_COUNT:-3}" -v size="${CFST_CHAMPION_POOL_SIZE:-10}" -v obs_file="$OBSERVATION_HISTORY_FILE" -v audit_file="$CHAMPION_LIFECYCLE_AUDIT_FILE" -v min_speed="${CFST_STABLE_SLOT_MIN_SPEED:-8}" -v stale_low_count="${CFST_OBSERVATION_STALE_LOW_COUNT:-3}" -v stable_max_low="${CFST_OBSERVATION_STABLE_MAX_LOW_COUNT:-1}" -v recent_window="${CFST_OBSERVATION_RECENT_WINDOW:-2}" -v prefer_regex="${CFST_STABLE_SLOT_PREFER_REGEX:-^104\\.17\\.}" -v avoid_regex="${CFST_STABLE_SLOT_AVOID_REGEX:-^(104\\.20\\.|104\\.26\\.|172\\.67\\.)}" '
    function classify(ip, recent_start, recent_lows) {
      if (obs_count[ip] == 0) return "challenger"
      recent_start=obs_count[ip] - recent_window + 1
      if (recent_start < 1) recent_start=1
      recent_lows=0
      for (k=recent_start; k<=obs_count[ip]; k++) if (obs_min[ip,k] < min_speed || obs_ok[ip,k] < 1) recent_lows++
      recent_low[ip]=recent_lows
      if (obs_low[ip] >= stale_low_count || recent_lows >= recent_window) return "stale"
      if (obs_low[ip] <= stable_max_low && obs_recent_min[ip] >= min_speed && obs_recent_ok[ip] >= 1) return "stable"
      return "watch"
    }
    function compute_stable_score(ip, score) {
      score=(obs_avg_min[ip] * 0.60) + (recent[ip] * 0.30) + (best_min[ip] * 0.10)
      if (health[ip] == "stable") score += 20
      else if (health[ip] == "watch") score += 5
      else if (health[ip] == "stale") score -= 1000
      else score -= 10
      if (ip ~ prefer_regex) score += 2
      if (ip ~ avoid_regex) score -= 5
      return score
    }
    function pass_ok(ip, idx) {
      return obs_min[ip,idx] >= min_speed && obs_ok[ip,idx] >= 1
    }
    function consecutive_passes(ip, idx, count) {
      for (idx=obs_count[ip]; idx>=1; idx--) {
        if (!pass_ok(ip, idx)) break
        count++
      }
      return count + 0
    }
    function consecutive_lows(ip, idx, count) {
      for (idx=obs_count[ip]; idx>=1; idx--) {
        if (pass_ok(ip, idx)) break
        count++
      }
      return count + 0
    }
    function lifecycle_state(ip) {
      if (health[ip] == "stable") return "stable"
      if (health[ip] == "watch") return "watch"
      if (health[ip] == "stale") return "stale"
      return "challenger"
    }
    function lifecycle_reason(ip) {
      if (health[ip] == "stable") return "recent_observation_passed;low_count_within_limit"
      if (health[ip] == "watch") return "observation_present;not_yet_stable"
      if (health[ip] == "stale") return "low_speed_or_failed_observation"
      return "no_observation_history_yet"
    }
    function promotion_ready(ip) {
      return health[ip] == "stable" && consecutive_pass[ip] >= recent_window && recent[ip] >= min_speed
    }
    BEGIN {
      while ((getline row < obs_file) > 0) {
        split(row, f, "\t")
        if (f[1] == "observed_at" || f[2] == "") continue
        ip=f[2]
        obs_count[ip]++
        idx=obs_count[ip]
        obs_min[ip,idx]=f[5]+0
        obs_ok[ip,idx]=f[7]+0
        obs_recent_min[ip]=f[5]+0
        obs_recent_ok[ip]=f[7]+0
        obs_sum_min[ip]+=f[5]+0
        obs_avg_min[ip]=obs_sum_min[ip] / obs_count[ip]
        if ((f[5]+0) < min_speed || (f[7]+0) < 1) obs_low[ip]++
      }
      close(obs_file)
    }
    FNR == NR {
      if (FNR > 1 && $1 != "") {
        ip=$1; best_min[ip]=$2+0; best_avg[ip]=$3+0; recent[ip]=$4+0; fail[ip]=$5+0; first[ip]=$6; last[ip]=$7; source[ip]=$8
        order[++order_count]=ip; seen[ip]=1
      }
      next
    }
    FNR > 1 && $1 != "" {
      ip=$1; min=$4+0; avg=$5+0; ok=$6+0
      if (!(ip in seen)) {
        order[++order_count]=ip; first[ip]=now; best_min[ip]=min; best_avg[ip]=avg; fail[ip]=0; source[ip]=$7; seen[ip]=1
      }
      recent[ip]=min; last[ip]=now
      if (min > best_min[ip]) best_min[ip]=min
      if (avg > best_avg[ip]) best_avg[ip]=avg
      if (source[ip] == "") source[ip]=$7
      else if (source[ip] !~ "(^|,)" $7 "(,|$)") source[ip]=source[ip] "," $7
      health[ip]=classify(ip)
      if (health[ip] == "stale" || min < degrade || min < champion_fail || (rounds > 0 && ok < rounds)) fail[ip]++
      else fail[ip]=0
    }
    END {
      print "ip\tbest_min_speed\tbest_avg_speed\trecent_min_speed\tfail_count\tfirst_seen\tlast_seen\tsource\thealth_status\tstable_score\trecent_low_count\tpool_type\tlifecycle_state\tlifecycle_reason\tobservation_count\tconsecutive_passes\tconsecutive_lows\tpromotion_ready"
      for (i=1; i<=order_count; i++) {
        ip=order[i]
        if (printed_seen[ip]) continue
        printed_seen[ip]=1
        if (fail[ip] >= evict) continue
        if (health[ip] == "") health[ip]=classify(ip)
        stable_score[ip]=compute_stable_score(ip)
        pool_type[ip]=(health[ip] == "stable" || health[ip] == "watch") ? "stable" : "competitive"
        consecutive_pass[ip]=consecutive_passes(ip)
        consecutive_low[ip]=consecutive_lows(ip)
        candidate[++candidate_count]=ip
      }
      for (i=1; i<=candidate_count; i++) {
        best=i
        for (j=i+1; j<=candidate_count; j++) {
          a=candidate[j]; b=candidate[best]
          score_a=stable_score[a]
          score_b=stable_score[b]
          if (score_a > score_b || (score_a == score_b && best_min[a] > best_min[b])) best=j
        }
        tmp=candidate[i]; candidate[i]=candidate[best]; candidate[best]=tmp
      }
      for (i=1; i<=candidate_count && i<=size; i++) {
        ip=candidate[i]
        state=lifecycle_state(ip)
        reason=lifecycle_reason(ip)
        ready=promotion_ready(ip) ? 1 : 0
        print ip "\t" best_min[ip] "\t" best_avg[ip] "\t" recent[ip] "\t" fail[ip] "\t" first[ip] "\t" last[ip] "\t" source[ip] "\t" health[ip] "\t" stable_score[ip] "\t" recent_low[ip]+0 "\t" pool_type[ip] "\t" state "\t" reason "\t" obs_count[ip]+0 "\t" consecutive_pass[ip]+0 "\t" consecutive_low[ip]+0 "\t" ready
      }
      for (i=1; i<=order_count; i++) {
        ip=order[i]
        if (fail[ip] >= evict) {
          if (health[ip] == "") health[ip]=classify(ip)
          stable_score[ip]=compute_stable_score(ip)
          print now "\t" ip "\tevicted\t" health[ip] "\t" fail[ip] "\t" stable_score[ip] "\t" lifecycle_reason(ip) >> audit_file
        }
      }
    }
  ' "$old" "$STABILITY_RESULT_FILE" > "$tmp"
  mv "$tmp" "$CHAMPION_POOL_FILE"
  log "冠军池：已更新 $CHAMPION_POOL_FILE，最多保留 ${CFST_CHAMPION_POOL_SIZE} 个 IP"
}

champion_report_command() {
  if [ ! -s "$CHAMPION_POOL_FILE" ]; then
    echo "champion pool is empty: $CHAMPION_POOL_FILE"
    return 0
  fi
  local generated_at
  generated_at="$(date '+%F %T')"
  {
    echo "=== champion-report ==="
    printf 'generated_at=%s\n' "$generated_at"
    printf 'champion_pool_file=%s\n' "$CHAMPION_POOL_FILE"
    printf 'lifecycle_audit_file=%s\n' "$CHAMPION_LIFECYCLE_AUDIT_FILE"
    printf 'stable_threshold=%s MB/s\n' "$CFST_STABLE_SLOT_MIN_SPEED"
    printf 'evict_fail_count=%s\n' "$CFST_FAIL_EVICT_COUNT"
    echo
    echo "=== summary ==="
    awk -F '\t' '
      NR == 1 {next}
      $1 != "" {
        total++
        health=$9 == "" ? "unknown" : $9
        pool=$12 == "" ? "unknown" : $12
        ready=$18 == "" ? "0" : $18
        health_count[health]++
        pool_count[pool]++
        if (ready == "1") ready_count++
        if (($5+0) > 0) failing_count++
      }
      END {
        printf "total=%d\n", total+0
        printf "stable=%d\n", health_count["stable"]+0
        printf "watch=%d\n", health_count["watch"]+0
        printf "challenger=%d\n", health_count["challenger"]+0
        printf "stale=%d\n", health_count["stale"]+0
        printf "promotion_ready=%d\n", ready_count+0
        printf "with_fail_count=%d\n", failing_count+0
        printf "stable_pool=%d\n", pool_count["stable"]+0
        printf "competitive_pool=%d\n", pool_count["competitive"]+0
      }
    ' "$CHAMPION_POOL_FILE"
    echo
    echo "=== promotion_ready ==="
    awk -F '\t' 'NR == 1 || $18 == "1" {print}' "$CHAMPION_POOL_FILE"
    echo
    echo "=== watch_or_stale ==="
    awk -F '\t' 'NR == 1 || $9 == "watch" || $9 == "stale" || ($5+0) > 0 {print}' "$CHAMPION_POOL_FILE"
    echo
    echo "=== top_by_stable_score ==="
    awk -F '\t' '
      NR == 1 {header=$0; next}
      $1 != "" {
        line[++n]=$0
        score[n]=$10+0
        best[n]=$2+0
      }
      END {
        print header
        for (i=1; i<=n; i++) {
          pick=i
          for (j=i+1; j<=n; j++) {
            if (score[j] > score[pick] || (score[j] == score[pick] && best[j] > best[pick])) pick=j
          }
          tmp=line[i]; line[i]=line[pick]; line[pick]=tmp
          tmp=score[i]; score[i]=score[pick]; score[pick]=tmp
          tmp=best[i]; best[i]=best[pick]; best[pick]=tmp
          if (i <= 10) print line[i]
        }
      }
    ' "$CHAMPION_POOL_FILE"
    echo
    echo "=== recent_evictions ==="
    if [ -s "$CHAMPION_LIFECYCLE_AUDIT_FILE" ]; then
      tail -n 20 "$CHAMPION_LIFECYCLE_AUDIT_FILE"
    else
      echo "no_audit_file"
    fi
  } | tee "$CHAMPION_REPORT_FILE"
}
