#!/usr/bin/env bash
# ==============================================================================
# Helper to format clean monthly calendar for Conky
# Highlights current day with bright cyan color markup
# ==============================================================================

python3 -c "
import calendar, datetime
now = datetime.datetime.now()
cal = calendar.monthcalendar(now.year, now.month)
print('\${color #94A3B8}Su  Mo  Tu  We  Th  Fr  Sa\${color #E2E8F0}')
for week in cal:
    line = []
    for day in week:
        if day == 0:
            line.append('  ')
        elif day == now.day:
            line.append(f'\${{color #00F0FF}}{day:2d}\${{color #E2E8F0}}')
        else:
            line.append(f'{day:2d}')
    print('  '.join(line))
" 2>/dev/null || cal 2>/dev/null || true
