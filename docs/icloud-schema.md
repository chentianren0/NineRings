# The CloudKit schema

[`CloudKit/NineRings.ckdb`](../CloudKit/NineRings.ckdb) is the schema of the app's iCloud container, `iCloud.com.chentianren.PlayNineRings`, written in CloudKit's schema language. This page says what it holds, how it is applied to the development environment, how it reaches production, and what can never change once it is there. The design behind it is section 5 of the iCloud design (`docs/icloud.md`).

A fact about Apple's platform names its source. A choice says it is one.

## What it holds

| Record type | Fields | Indexes |
|---|---|---|
| `Toy` | `format` (`ENCRYPTED INT64`), `payload` (`ENCRYPTED BYTES`) | none |
| `FinishedPlay` | `format` (`ENCRYPTED INT64`), `payload` (`ENCRYPTED BYTES`) | none |
| `Users` | CloudKit's own type, in every container | as CloudKit has it |

The records live in one custom zone of the private database. The app makes the zone; the schema does not name zones.

- **`format` is `ENCRYPTED INT64` and `payload` is `ENCRYPTED BYTES`**, because the app writes them through `CKRecord.encryptedValues`, as an `Int` and as `Data`. Apple's grammar allows `ENCRYPTED` with `BYTES`, `STRING`, `DOUBLE`, `INT64`, `LOCATION` and `TIMESTAMP` ("Integrating a Text-Based Schema into Your Workflow").
- **No indexes.** The sync engine fetches changes and never queries. An encrypted field cannot have an index anyway (Apple, "Encrypting User Data").
- **No permissions on the app's types.** Apple's grammar says a `GRANT` sets permissions in the public database, and that a type without one cannot be used there. The app keeps nothing in the public database. This is a choice: no one can put records of these types there.
- **`Users`** is written as CloudKit exports it, so that applying the file leaves that type as it is.
- **Comments.** The file has `//` comments, which the grammar allows. CloudKit does not keep them, and an export can list the types in another order (the same article).

## What the environments held on 20 November 2026

Read with `cktool export-schema` (version 1.0.23001, from Xcode 27.3) at 02:13 UTC, which only reads:

- **Development** held `Toy`, `FinishedPlay` and `Users`, and nothing else. `Toy` and `FinishedPlay` had `format ENCRYPTED INT64` and `payload ENCRYPTED BYTES`, CloudKit's six system fields (`___createTime`, `___createdBy`, `___etag`, `___modTime`, `___modifiedBy`, `___recordID`), no index on any field, and no `GRANT`. `Users` was as in the file. This is the file, with the system fields that every type has.
- **Production** held `Users` alone.

The probe ([icloud-probe.md](icloud-probe.md)) then saved about 450 records of both types into development, as the app writes them, and no save was refused for its record type or its fields. Exports after its runs, at 02:43 and 11:11 UTC, were the same as the one above.

## Applying it to the development environment

Applying the schema is the owner's step. `cktool` comes with Xcode (`xcrun cktool`). Its schema commands authenticate with a **management token**, which the owner creates in CloudKit Console and saves on the Mac once:

```bash
xcrun cktool save-token --type management
```

It asks for the token and keeps it in the login keychain. In the commands below, `$TEAM_ID` is the project's `DEVELOPMENT_TEAM`.

Read what the development environment holds, to compare it with the file:

```bash
xcrun cktool export-schema --team-id "$TEAM_ID" --container-id iCloud.com.chentianren.PlayNineRings --environment development --output-file development.ckdb
```

Check the file against the container:

```bash
xcrun cktool validate-schema --team-id "$TEAM_ID" --container-id iCloud.com.chentianren.PlayNineRings --environment development --file CloudKit/NineRings.ckdb
```

Apply it:

```bash
xcrun cktool import-schema --team-id "$TEAM_ID" --container-id iCloud.com.chentianren.PlayNineRings --environment development --validate --file CloudKit/NineRings.ckdb
```

Apple's article says CloudKit applies a file only if nothing that production holds would be lost, such as a record type or a field already there, and otherwise changes nothing. Resetting the development environment (in CloudKit Console, or `xcrun cktool reset-schema`) makes it match production and deletes all of its data (`cktool help reset-schema`); the file is then imported again.

In development, CloudKit also adds a field by itself when a saved record carries one that the schema lacks (Apple, "Encrypting User Data"). A debug build that wrote another field would therefore change the development schema, and the next deployment would carry that field to production. Comparing an export with this file before deploying catches it.

## Getting it to production

Production gets the schema **by hand, in CloudKit Console, once, before the first release** that uses it. TestFlight builds use production too, so this comes before the first TestFlight build with the new backend. `cktool` has no command that deploys to production; Apple's article "Deploying an iCloud Container's Schema" puts that step in CloudKit Console.

1. Make the development environment hold exactly this file: export it, compare it with the file, and if they differ, reset and import as above. Deploying copies every record type, field and index of the development schema, but no records (Apple, "Deploying an iCloud Container's Schema").
2. In CloudKit Console, deploy the schema changes of the container to production.

## What can never change afterwards

Once the schema is in production:

- **`Toy` and `FinishedPlay` stay, with their names**, and so do their fields `format` and `payload`. Record types and fields in production can be neither deleted nor renamed (Apple, "Deploying an iCloud Container's Schema").
- **Each field keeps its type and its encryption.** A field can be encrypted only when it is introduced (Apple, "Encrypting User Data").
- **What can still change:** new record types and new fields can be added, by deploying again (Apple, "Designing and Creating a CloudKit Database").

Because `payload` is opaque to CloudKit and `format` says which version of its JSON it holds, a later change to what the app stores needs no change to this schema (section 14 of the design).
