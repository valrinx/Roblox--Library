# Obsidian Bases Skill
## Workflow
1. **Create the file**: Create a `.base` file in the vault with valid YAML content
2. **Define scope**: Add `filters` to select which notes appear (by tag, folder, property, or date)
3. **Add formulas** (optional): Define computed properties in the `formulas` section
4. **Configure views**: Add one or more views (`table`, `cards`, `list`, or `map`) with `order` specifying which properties to display
5. **Validate**: Verify the file is valid YAML with no syntax errors
6. **Test in Obsidian**: Open the `.base` file to confirm the view renders correctly

## Schema
```yaml
filters:
  and:
    - 'status == "active"'
    - not:
        - 'file.hasTag("archived")'
formulas:
  formula_name: 'expression'
properties:
  property_name:
    displayName: "Display Name"
  formula.formula_name:
    displayName: "Formula Display Name"
views:
  - type: table | cards | list | map
    name: "View Name"
    limit: 10
    order:
      - file.name
      - property_name
    summaries:
      property_name: Average
```

## Filter Syntax
```yaml
filters: 'status == "done"'
filters:
  and:
    - 'status == "done"'
    - 'priority > 3'
filters:
  or:
    - 'file.hasTag("book")'
    - 'file.hasTag("article")'
filters:
  not:
    - 'file.hasTag("archived")'
```

### Filter Operators
| Operator | Description |
|----------|-------------|
| `==` | equals |
| `!=` | not equal |
| `>` | greater than |
| `<` | less than |
| `>=` | greater than or equal |
| `<=` | less than or equal |
| `&&` | logical and |
| `\|\|` | logical or |
| `!` | logical not |

## Properties
1. **Note properties** - From frontmatter: `note.author` or just `author`
2. **File properties** - File metadata: `file.name`, `file.mtime`, etc.
3. **Formula properties** - Computed values: `formula.my_formula`

### File Properties Reference
| Property | Type | Description |
|----------|------|-------------|
| `file.name` | String | File name |
| `file.basename` | String | File name without extension |
| `file.path` | String | Full path to file |
| `file.folder` | String | Parent folder path |
| `file.ext` | String | File extension |
| `file.size` | Number | File size in bytes |
| `file.ctime` | Date | Created time |
| `file.mtime` | Date | Modified time |
| `file.tags` | List | All tags in file |
| `file.links` | List | Internal links in file |
| `file.backlinks` | List | Files linking to this file |

## Formula Syntax
```yaml
formulas:
  total: "price * quantity"
  status_icon: 'if(done, "✅", "⏳")'
  formatted_price: 'if(price, price.toFixed(2) + " dollars")'
  created: 'file.ctime.format("YYYY-MM-DD")'
  days_old: '(now() - file.ctime).days'
  days_until_due: 'if(due_date, (date(due_date) - today()).days, "")'
```

### Key Functions
| Function | Signature | Description |
|----------|-----------|-------------|
| `date()` | `date(string): date` | Parse string to date |
| `now()` | `now(): date` | Current date and time |
| `today()` | `today(): date` | Current date |
| `if()` | `if(condition, trueResult, falseResult?)` | Conditional |
| `duration()` | `duration(string): duration` | Parse duration string |
| `file()` | `file(path): file` | Get file object |
| `link()` | `link(path, display?): Link` | Create a link |

### Duration Type
When subtracting two dates, the result is a **Duration** type.
**Duration Fields:** `.days`, `.hours`, `.minutes`, `.seconds`, `.milliseconds`
**IMPORTANT:** Duration does NOT support `.round()` directly. Access a numeric field first.
```yaml
# CORRECT
"(date(due_date) - today()).days"
"(now() - file.ctime).days.round(0)"
# WRONG - will cause error
# "((date(due) - today()) / 86400000).round(0)"
```

## View Types
- **table** - Spreadsheet-like view
- **cards** - Card/gallery view
- **list** - Simple list view
- **map** - Requires latitude/longitude properties and Maps plugin

## Default Summary Formulas
| Name | Input Type | Description |
|------|------------|-------------|
| `Average` | Number | Mathematical mean |
| `Min` | Number | Smallest number |
| `Max` | Number | Largest number |
| `Sum` | Number | Sum of all numbers |
| `Range` | Number | Max - Min |
| `Median` | Number | Mathematical median |
| `Earliest` | Date | Earliest date |
| `Latest` | Date | Latest date |
| `Checked` | Boolean | Count of true values |
| `Unchecked` | Boolean | Count of false values |
| `Empty` | Any | Count of empty values |
| `Filled` | Any | Count of non-empty values |
| `Unique` | Any | Count of unique values |

## Embedding Bases
```markdown
![[MyBase.base]]
![[MyBase.base#View Name]]
```

## YAML Quoting Rules
- Use single quotes for formulas containing double quotes: `'if(done, "Yes", "No")'`
- Use double quotes for simple strings: `"My View Name"`

## Common Formula Errors
**Duration math without field access**: Always access `.days`, `.hours` first.
**Missing null checks**: Use `if()` to guard properties that may not exist.
**Referencing undefined formulas**: Ensure every `formula.X` has a matching entry in `formulas`.

## References
- [Bases Syntax](https://help.obsidian.md/bases/syntax)
- [Functions](https://help.obsidian.md/bases/functions)
- [Views](https://help.obsidian.md/bases/views)
