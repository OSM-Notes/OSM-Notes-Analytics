# ToDo Directory

This directory contains progress tracking and workflow notes for the OSM-Notes-Analytics project.
Task backlogs are maintained in `Progress_Tracker.md` and, for larger items, GitHub issues.

---

## Files Overview

### Progress_Tracker.md

**Purpose**: Sprint focus, weekly log, quick stats, next items, blockers  
**Use for**:

- Sprint planning
- Daily updates
- Weekly reviews
- Quick statistics

**How to use**:

1. Update weekly goals at start of sprint
2. Log daily progress in weekly section
3. Update quick stats table
4. Track blockers and decisions

**Status markers** (when you use checklists in this file or in issues):

- `[ ]` Not started
- `[🔄]` In progress
- `[✅]` Completed
- `[❌]` Cancelled/Not needed

**Update frequency**: Daily or as tasks complete

---

## Workflow

### Starting a New Sprint

1. Review `Progress_Tracker.md` for next priority items
2. Set sprint goals in `Progress_Tracker.md`
3. Create GitHub issues for major tasks (optional)
4. Mark items as [🔄] in progress

### During Development

1. Work on tasks from current sprint
2. Update `Progress_Tracker.md` with daily progress
3. Mark completed items [✅] in `Progress_Tracker.md` or linked issues
4. Document blockers in `Progress_Tracker.md`

### Sprint Review

1. Update statistics in `Progress_Tracker.md`
2. Log completed items
3. Plan the next sprint
4. Review and adjust priorities if needed

### Adding New Tasks

1. Add an entry or checklist item in `Progress_Tracker.md`, or open a GitHub issue
2. Assign priority level
3. Update statistics if you use the quick stats table
4. Pull critical work into the current sprint when needed

---

## Priority Guidelines

### Critical

- Breaking bugs or data quality issues
- Test failures preventing deployment
- Critical missing functionality
- **Timeline**: Fix immediately

### High

- Important missing features
- Significant accuracy improvements
- High-impact metrics
- **Timeline**: Fix within 1-2 weeks

### Medium

- Enhancements and optimizations
- Code quality improvements
- Documentation updates
- **Timeline**: Fix within 1-2 months

### Low

- Nice-to-have features
- Future enhancements
- Documentation polish
- **Timeline**: As time permits

---

## Task Categories

- **Test Failures**: Data quality and validation
- **Missing Metrics**: Dashboard and analytics gaps
- **Code Quality**: Refactoring and improvements
- **Performance**: Query and processing optimizations
- **Documentation**: Guides and references
- **Future**: Long-term enhancements

---

## Integration with Development

### Git Workflow

When working on tracked tasks:

```bash
# Create branch for task
git checkout -b fix/test-failures-datamarts

# Make changes
# ...

# Commit with reference
git commit -m "Fix: datamart calculation tests

Fixes failing tests in resolution metrics
Updates test expectations to match actual data

Related files:
- tests/unit/bash/datamart_resolution_metrics.test.bats"

# Update Progress_Tracker.md or the linked GitHub issue
```

### GitHub Issues (Optional)

For major tasks, create GitHub issues:

```markdown
Title: Add resolution time aggregates to datamarts

**Reference**: ToDo/Progress_Tracker.md (link or section)  
**Priority**: High

**Description**: Missing resolution time analytics in datamarts.

**Impact**: Critical for problem notes analysis

**Files**:

- sql/dwh/datamartCountries/
- sql/dwh/datamartUsers/
```

---

## Current Focus Areas

Based on analysis in `docs/DASHBOARD_ANALYSIS.md`:

### Priority 1: Fix Current Issues

- Fix failing unit tests
- Verify datamart accuracy

### Priority 2: Add Missing Metrics

- Resolution time analytics (⭐⭐⭐⭐⭐)
- Community health indicators (⭐⭐⭐⭐⭐)
- Application statistics (⭐⭐⭐⭐)
- Content quality metrics (⭐⭐⭐⭐)
- User behavior patterns (⭐⭐⭐⭐)

### Priority 3: Polish

- Documentation updates
- Performance baselines
- Dashboard guides

---

## Tips

1. **Be realistic**: Don't mark items as done unless fully complete
2. **Document blockers**: If stuck, note why in `Progress_Tracker.md`
3. **Update regularly**: Keep the tracker and issues in sync
4. **Use references**: Link commits, PRs, and issues
5. **Celebrate wins**: Log completed items in `Progress_Tracker.md`
6. **Adjust priorities**: Move urgent items up as needed
7. **Break down large tasks**: Split into smaller, actionable items

---

## Contact

If you discover new bugs or have feature ideas:

1. Add them to `Progress_Tracker.md` or create a GitHub issue
2. Assign priority
3. Update quick stats if you maintain them

---

**Maintained By**: Project contributors
