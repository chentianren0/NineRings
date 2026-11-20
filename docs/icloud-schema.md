# The CloudKit schema

[`CloudKit/NineRings.ckdb`](../CloudKit/NineRings.ckdb) is the schema of the app's iCloud container, `iCloud.com.chentianren.PlayNineRings`, written in CloudKit's schema language. This page says what it holds, how it is applied to the development environment, how it reaches production, and what can never change once it is there. The design behind it is in section 5 of the iCloud design.

As elsewhere in these pages, a fact about Apple's platform names its source, a choice says it is one, and what is not yet known says so.

## What it holds

| Record type | Fields | Indexes |
|---|---|---|
| `Toy` | `format` (encrypted 64-bit integer), `payload` (encrypted bytes) | none |
| `FinishedPlay` | `format` (encrypted 64-bit integer), `payload` (encrypted bytes) | none |
| `Users` | CloudKit's own type, in every container | as CloudKit has it |

The records live in one custom zone of the private database. The zone is made by the app, not by the schema.

- **No indexes.** The app's sync engine fetches changes and never queries, and an encrypted field cannot be indexed or queried anyway (Apple, `CKRecord.encryptedValues` and "Encrypting User Data").
- **No permissions for the app's types.** Apple's grammar says a `GRANT` clause sets permissions in the public database, and that a type without one cannot be used there. The app keeps nothing in the public database, so its types grant nothing, and no one can put records of them there. This is a choice. A type that CloudKit creates by itself in development, when a record of it is first saved, comes with three permissions (`WRITE` to `_creator`, `CREATE` to `_icloud`, `READ` to `_world`): applying this file takes them away.
- **`format` is `ENCRYPTED INT64` and `payload` is `ENCRYPTED BYTES`**, because the app writes them through `encryptedValues` as an `Int` and as `Data`. CloudKit gives them the same types when it creates them by itself from such records (observed on 19 November 2026; see the probe's question 13 in [icloud-probe.md](icloud-probe.md)).
- **`Users`** is written as CloudKit exports it, so that applying the file leaves the type as it is.

**Checked against Apple's grammar** ("Integrating a Text-Based Schema into Your Workflow", in the documentation of Xcode 27.3, read on 19 November 2026). The grammar allows `ENCRYPTED` with `BYTES`, `STRING`, `DOUBLE`, `INT64`, `LOCATION` or `TIMESTAMP`. Identifiers begin with a letter. Comments in `//` form are allowed, and CloudKit does not keep them. System fields, whose names begin with underscores, are written in double quotes.

**Checked against the container** on 19 November 2026, with `cktool` 1.0.23001 from Xcode 27.3:

- `xcrun cktool validate-schema` for the development environment answered "Schema is valid."
- `export-schema` for development, after the probe had saved its records, showed `Toy` and `FinishedPlay` with `format ENCRYPTED INT64` and `payload ENCRYPTED BYTES`, each with CloudKit's six system fields (`___createTime`, `___createdBy`, `___etag`, `___modTime`, `___modifiedBy`, `___recordID`) without indexes and with the three permissions above, and `Users` exactly as in the file. No other record type was there.
- `export-schema` for production showed `Users` alone.
- `import-schema --validate` then applied the file to development. The export afterwards matched the file: the two types kept their fields and lost the three permissions. The probe's saves, refusals and fetches worked the same on the imported schema, and left it unchanged.

## Applying it to the development environment

`cktool` comes with Xcode (`xcrun cktool`, version 1.0.23001 in Xcode 27.3). Schema commands authenticate with a **management token**, which the owner creates once in CloudKit Console, under the account's Settings, and saves on the Mac:

```bash
xcrun cktool save-token --type management
```

It asks for the token and keeps it in the login keychain. The team id below is the project's `DEVELOPMENT_TEAM`.

Check the file against the container without changing anything:

```bash
xcrun cktool validate-schema --team-id "$TEAM_ID" --container-id iCloud.com.chentianren.PlayNineRings --environment development --file CloudKit/NineRings.ckdb
```

Apply it:

```bash
xcrun cktool import-schema --team-id "$TEAM_ID" --container-id iCloud.com.chentianren.PlayNineRings --environment development --validate --file CloudKit/NineRings.ckdb
```

Read back what the development environment holds, to compare it with the file:

```bash
xcrun cktool export-schema --team-id "$TEAM_ID" --container-id iCloud.com.chentianren.PlayNineRings --environment development --output-file /tmp/development.ckdb
```

Apple's article says CloudKit applies a file only if doing so would lose nothing that production holds, such as a record type or a field already there; otherwise it changes nothing. It may also list the elements of an exported schema in a different order from the file.

### The old types in development

The earlier design's record types, which Core Data made (`CD_FinishedPlay`, `CD_SavedToy` and its own), were expected in the development environment, but the export on the evening of 19 November 2026 (Pacific time) showed none of them: only `Toy`, `FinishedPlay` and `Users`. Nothing but `Users` is in production. On that evening the file was imported into development, which since then holds exactly what the file says. Resetting the development environment (in CloudKit Console, "Reset Environment", or `xcrun cktool reset-schema`) deletes every record and, while nothing is in production, every record type there (Apple, "Deploying an iCloud Container's Schema" and `cktool help reset-schema`). After a reset the file is imported as above. The reset is the owner's to do.

## Getting it to production

Production gets the schema **by hand, in CloudKit Console, once, before the first release**. TestFlight builds use production too, so this comes before the first TestFlight build. `cktool` has no command that deploys to production; Apple's article puts that step in CloudKit Console.

1. Make the development environment hold exactly this file: reset it, import the file, export it, and compare. Deploying copies **every** record type, field and index of the development schema, but no records (Apple, "Deploying an iCloud Container's Schema"). An old `CD_` type, or a field that a debug build or the probe created by saving a record, would go to production for good.
2. In CloudKit Console, open CloudKit Database, choose the container, and deploy the schema changes to production. This needs the right to edit production.

## What can never change afterwards

Once the schema is in production:

- **`Toy` and `FinishedPlay` stay, with their names**, and so do their fields `format` and `payload`. Record types and fields in production can be neither deleted nor renamed (Apple, "Deploying an iCloud Container's Schema"; WWDC21 session 10118).
- **Each field keeps its type and its encryption.** `format` stays an encrypted integer and `payload` encrypted bytes. A field can be encrypted only when it is introduced (Apple, "Encrypting User Data").
- **What can still change:** new record types and new fields can be added, by deploying again. Indexes can be added and removed, and permissions changed, in production (WWDC21 session 10118).

Because `payload` is opaque to CloudKit and `format` says which version of its JSON it holds, a later change to what the app stores needs no change to this schema (choice 7 of the design).
