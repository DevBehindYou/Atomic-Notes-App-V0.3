# Tag limits

New tags are limited to five per note and 15 visible Unicode characters per tag.
The tag field and document model share the same limits. Whitespace trimming and
case-insensitive deduplication happen before counting; rejected model mutations
leave the draft untouched. Emoji and combined characters count as one visible
character, matching Flutter's text-field counter.

Older notes may already contain up to 12 tags or tags of up to 40 UTF-16 units.
Opening or editing their text preserves those saved tags without truncation.
Existing tags can always be removed; adding a tag requires the resulting count
to be five or fewer, and every new tag must satisfy the 15-character limit.
Removing a legacy tag does not allow adding it back outside the new limits.

The content envelope, encryption and sync formats are unchanged. Regressions
cover the five/six and 15/16 boundaries, Unicode storage roundtrips, duplicate
normalization, legacy-note preservation/removal, and the editor's input/add guard.
