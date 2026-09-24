# nf-core/taxmarker: Weighted clustering

Before anything else sees the input (alignment, raxtax, placement), the pipeline reduces it to one representative sequence per (cluster, taxon) pair.
This collapses near-duplicate sequences of the same taxon -- common in real reference databases such as GTDB, which can carry dozens of genomes per species -- before the much more expensive downstream steps run on them.

Three parameters control this, all optional:

- `--sequence_weights`: a two-column table (`sequence_id<TAB>weight`) used to break ties when picking a representative.
  Sequences absent from the table default to weight 1.
  Omit entirely and every sequence is weight 1, which degrades to "pick the longest sequence per (cluster, taxon) pair".
  See [issue #15](https://github.com/nf-core/taxmarker/issues/15) for a GTDB-metadata-derived recipe for turning genome quality/category/taxonomy-agreement signals into this table -- the clustering logic itself is generic and doesn't care where the weights came from.
- `--min_weight`: an absolute cutoff applied before clustering.
  Sequences below it are excluded outright, regardless of `--sequence_weights`.
  Has no effect unless both this and `--sequence_weights` are set -- relative per-cluster selection alone can't exclude a badly-mislabeled sequence that never co-clusters with anything (e.g. a singleton cluster).
- `--cluster_identity`: the [VSEARCH](https://github.com/torognes/vsearch) clustering identity threshold, 0-1, default `1.0`.
  The default is a safe no-op: pure dereplication of exact/near-identical duplicates.
  Lower it for more aggressive input-size reduction on very large datasets.

## How VSEARCH decides what counts as "identical"

`--cluster_identity` doesn't mean what a quick reading suggests, so it's worth spelling out exactly what VSEARCH does, confirmed against its own manual (`man vsearch`, v2.32.0):

- VSEARCH always aligns the full length of both sequences against each other with a global Needleman-Wunsch algorithm (full dynamic programming) -- never a local/Smith-Waterman alignment restricted to the best-matching region.
- Terminal gaps (a dangling, non-overlapping end on either sequence) get a much cheaper gap penalty than internal gaps by default (open 2 vs. 20, extend 1 vs. 2), so a non-overlapping end is simply gapped out rather than forced into mismatches.
- The identity score itself (`--iddef 2`, VSEARCH's own default) is `matches / (alignment length - terminal gaps)`: terminal-gap columns are excluded from **both** the numerator and the denominator.

The consequence: identity reflects only the _overlapping_ region between two sequences, and the overlap's length relative to either full sequence plays no role in the score.
Two sequences that only partially overlap -- each with its own unique, non-overlapping end -- can still reach 100% identity and be clustered together, provided the shared middle matches perfectly, no matter how small a fraction of either sequence's total length that shared region is.
Conversely, mismatches that fall _inside_ the shared/aligned region (not at the ends) always count against identity, so genuinely divergent sequences are correctly kept apart at the pipeline's default `--cluster_identity 1.0`.

This is what lets the pipeline's default settings correctly merge, say, a full-length 16S sequence and a shorter deposited fragment of the same organism (the fragment's implied "missing" tail is just a terminal gap on the longer sequence).
The corresponding risk -- a short, spuriously-identical overlap merging two sequences that shouldn't be merged -- is bounded downstream: representative selection groups by `(cluster, taxon)`, so a cross-taxon spurious merge can't produce a wrong cross-taxon representative; only a same-taxon spurious merge could pick between two genuinely different same-species fragments, which the pipeline treats as an acceptable simplification for its purpose (one representative sequence per taxon, not preservation of every individual record).
