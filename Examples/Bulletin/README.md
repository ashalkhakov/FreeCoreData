# Bulletin

The FreeCoreData **persistent history** example: a message board written
twice.

Bulletin runs *two complete Core Data stacks in one process* — two
`NSPersistentContainer`s, two coordinators, two view contexts — on the
**same store file**. Each stack gets its own window and its own
`transactionAuthor` (`alice`, `bob`). That makes one process behave like
the app-plus-extension or app-plus-daemon setups persistent history was
designed for: a save by one stack is invisible to the other's contexts
until the other stack notices it and merges it. Type a post in alice's
window and watch it appear in bob's; the History window shows the
transaction log driving it, live.

## The API tour

Every part of the persistent-history API has one home here:

| API | Where |
| --- | ----- |
| `NSPersistentHistoryTrackingKey`, `NSPersistentStoreRemoteChangeNotificationPostOptionKey` | `BLAppDelegate` sets both options on the store description |
| `NSPersistentStoreRemoteChangeNotification` | both window controllers listen; it is a contentless doorbell — *schedule* work from the handler, never touch a context in it synchronously |
| `transactionAuthor` | `BLBoardWindowController` init; each stack's identity in the log |
| `fetchHistoryAfterToken:` + settable `fetchRequest` with `author != %@` | `-[BLBoardWindowController mergeNewHistory]` — the canonical consumer: "only what is new, only from other writers" |
| `NSPersistentHistoryTransaction.objectIDNotification` → `mergeChangesFromContextDidSaveNotification:` | same method — how history is replayed into a context |
| `currentPersistentHistoryTokenFromStores:` | same method — advancing the merge position |
| `NSPersistentHistoryToken` as `NSSecureCoding` | `-saveMergePosition` / `-restoreMergePosition` archive it to user defaults, so a relaunch resumes where it stopped |
| `fetchHistoryAfterDate:`, transactions + changes, `updatedProperties` | `-[BLHistoryWindowController reloadHistory]` renders the log |
| tombstones (`preserveValueOnDeletion` on `Post.text`) | delete a post, then look at its history row: the text survives in the tombstone |
| `NSPersistentHistoryResultTypeCount` | `-transactionCount` |
| `deleteHistoryBeforeDate:` | **Compact History** — and the *safe purge floor*: only history that every consumer has merged may go, so the floor is the oldest merged-through moment across the boards |

Notes a porter should not have to rediscover (all macOS-arbitrated, see
`NSPersistentHistoryChangeRequest.h`):

- Build history fetch requests from `entityDescriptionWithContext:`;
  Apple's context-less `+fetchRequest` / `+entityDescription` answer nil
  unless a loaded container lets CoreData find "the" model.
- A `Change`-entity fetch request answers the matching changes
  themselves, not transactions.
- Sort descriptors on a history fetch **raise** on Apple for every
  public keypath; history arrives in transaction order.
- Set the consuming context's `stalenessInterval` to 0. Apple caches
  fetched rows per coordinator and a refresh refetches through that
  cache, so with the default (infinite) interval another stack's writes
  stay invisible even after a merge.

## Building

GNUstep, with the FreeCoreData framework and `momc` built:

```sh
make            # momc on PATH, or: make MOMC=/path/to/momc
openapp ./Bulletin.app
```

macOS: open `Bulletin.xcodeproj` and run the **Bulletin** scheme, or

```sh
xcodebuild -project Bulletin.xcodeproj -scheme Bulletin build
```

It builds the same sources, XIBs and `Bulletin.xcdatamodeld` against
Apple's CoreData — that is the point of the exercise. Codegen for the
model is off; `BLManagedObjects.*` are the hand written classes.

The store lives in `Application Support/Bulletin.sqlite`; the merge
tokens live in user defaults under `BLMergedToken.*`.
