# Delphi Code Style

These rules apply to all generated Object Pascal code in this project.

## Naming

- Private class fields begin with lowercase `f`, e.g. `fIndex: Integer;`
- Unit filenames use prefixes: `u_` for general units, `f_` for form units
- Types use `T` prefix (records, classes, enums) per Delphi convention
- use lowercase "a" for method argument prefixes

## Comments

- Use simple `//` comments on classes and methods — do not use XML-doc `<summary>` style comments

## Formatting

- Indent a `begin`/`end` pair under a `case` statement's enum identifier:

```pascal
case Mode of
  lmFullWindow:
    begin
      // ...
    end;
  lmPanelAndFlight:
    begin
      // ...
    end;
end;
```

## Memory Management

- Do not use `FreeAndNil` in a destructor — use plain `.Free` instead
- The owning class is responsible for freeing objects it creates

## General

- Keep units focused: one primary concern per unit
- Use `Single` for all floating-point game state (not `Double`)
- Prefer records for value types (state, criteria, pads) and classes for reference types (profiles, scenes)
