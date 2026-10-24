# nf-core/taxmarker: Choosing `--cluster_identity`

> **Work in progress.**
> The numbers on this page come from one run on bacterial 16S sequences from GTDB release 232 and will be measured again before the first release.
> The placements in these runs used GTR+G instead of the RAxML-NG model of the reference tree, which a later fix corrects, so the flag counts will change.

[Weighted clustering](weighted_clustering.md) reduces the input to one representative per (cluster, taxon) pair before alignment, raxtax and placement.
`--cluster_identity` sets how similar two sequences must be to share a cluster.
At the default `1.0` only identical and near-identical sequences are merged.
A lower value gives a smaller reference tree and a faster, less memory-hungry placement, at the price of fewer sequences being tested.
This page shows what that price was in one large run.

## What was run

The input was all 1,118,534 bacterial sequences in GTDB's `ssu_all_r232.fna.gz`, with `--upstream GTDB` weights, the raxtax prefilter on, and the same tree search settings and seed in both runs.
One run used `--cluster_identity 1.0` and the other `--cluster_identity 0.97`.
The placement ran 25 folds, one per job.

## Size and cost

|                                            | `1.0`        | `0.97`        |
| ------------------------------------------ | ------------ | ------------- |
| Representatives after clustering           | 318,358      | 148,034       |
| After the raxtax prefilter                 | 299,245      | 133,470       |
| Placed and scored (after profile coverage) | 239,806      | 92,406        |
| Peak memory of one placement fold          | 414.5 GB     | 135.6 GB      |
| Time of one placement fold                 | about 42 min | about 4.5 min |
| Scoring step                               | 1 h 6 min    | 10 min 48 s   |
| SATIVA flags                               | 40,587       | 11,590        |

At `1.0` the folds ran one after the other and took about 17.5 hours in all.
At `0.97` they ran three at a time with 300 GB each, and the whole pipeline finished in 2 h 17 min.
Memory per fold fell a little faster than the number of sequences (to 0.33 of the memory for 0.39 of the sequences), and time fell much faster (to 0.11).
Only two sizes were measured, so do not extrapolate these ratios.

### Going below `0.97` saves little

The number of representatives cannot fall below the number of distinct taxa in the input, 96,125 here, because every taxon keeps at least one.

| `--cluster_identity` | Representatives |
| -------------------- | --------------- |
| `1.0`                | 318,358         |
| `0.99`               | 164,357         |
| `0.97`               | 148,034         |
| `0.95`               | 144,183         |
| `0.9`                | 139,416         |

Most of the reduction happens between `1.0` and `0.97`.
Going from `0.97` to `0.9` removes 6% of the representatives and loses more flags.

## What clustering does to the flags

A flag is a sequence whose placement disagrees with its declared taxonomy.
Each flag has a mismatch rank, the highest rank where they disagree: 1 domain, 2 phylum, 3 class, 4 order, 5 family, 6 genus, 7 species.

Flags depend on the sequences that stay in the tree.
The table compares the two runs on the 89,538 sequences that were placed in both:

| Rank | `1.0` flags | Also flagged at `0.97` |
| ---- | ----------- | ---------------------- |
| 2    | 2,714       | 93%                    |
| 3    | 361         | 93%                    |
| 4    | 665         | 89%                    |
| 5    | 704         | 85%                    |
| 6    | 1,544       | 66%                    |
| 7    | 4,674       | 35%                    |

Species-level flags depend on which sister species are in the tree, so they change when sequences are removed.
Flags at higher ranks mostly stay.

A flagged sequence that is not a representative at `0.97` is not placed itself.
It still counts as caught if its representative (same cluster and taxon) is flagged by SATIVA or raxtax, because a cluster member inherits its representative's verdict.
Counting that, `0.97` catches these shares of the 40,587 flags of the `1.0` run:

| Rank | `1.0` flags | Caught at `0.97` |
| ---- | ----------- | ---------------- |
| 2    | 3,892       | 83%              |
| 3    | 422         | 93%              |
| 4    | 769         | 87%              |
| 5    | 815         | 85%              |
| 6    | 8,417       | 56%              |
| 7    | 26,272      | 39%              |
| All  | 40,587      | 49%              |

Clustering to `0.97` therefore loses about half of the genus-level flags and over half of the species-level ones, which are also the largest group.

## Checking flags against NCBI

To see whether the flags that disappeared were right, the sequences were compared with the NCBI RefSeq 16S database (`blastn`, original sequences).
A top hit with at least 97% identity and 90% coverage was counted as strong.
The phylum of the hit was taken from the hit's genus through the GTDB taxonomy of the same run.
Of the 3,892 phylum-level flags of the `1.0` run, 1,507 had only weak hits, because the database has no close relative, so they cannot be judged this way.

For the flags with a strong hit:

- Flags found in both runs were mostly right: the hit lay in the phylum the flag moved the sequence to for 1,063 of 1,161.
- Flags found only at `1.0` were mostly wrong: for the 404 whose representative was not flagged at `0.97`, the hit lay in the declared phylum for 386.
  These are sequences whose placement moved when sequences were removed from the tree, a pattern consistent with long-branch artefacts, which has not been tested.
- 97 flags that look right had no representative flagged, about 7% of the phylum-level flags that look right.

For species with many sequences (_Escherichia coli_, _Klebsiella pneumoniae_, _Staphylococcus aureus_, _Salmonella enterica_, _Pseudomonas aeruginosa_), more than 99% of the sequences that were not flagged had a top hit in the expected genus.
A genus-level comparison cannot say anything about species-level flags, because 16S sequences of closely related species are too similar.

At the phylum level `0.97` therefore dropped many flags that looked wrong and missed few that looked right.
At genus and species level the loss is larger and could not be checked this way.

## With and without the raxtax prefilter

The `0.97` run was repeated with `--skip_raxtax`.
Without the prefilter 99,166 sequences were placed instead of 92,406, and SATIVA flagged 17,812 instead of 11,590.
One placement fold needed 145.7 GB instead of 135.6 GB.

raxtax flagged 14,564 sequences, all at genus level.
Of these, 7,390 fail the profile coverage filter and are never placed, so SATIVA could not have flagged them.
The other 7,174 are placed when raxtax is skipped, and SATIVA flags 5,329 of them (74%).

The two runs also differ in the flags on the remaining sequences.
Of the 91,992 sequences placed in both runs, 8,861 flags are shared, 2,575 are found only with raxtax, and 3,622 only without it.
Checking the 3,622 against NCBI as above, most flags with a strong hit at phylum to family level point to the declared taxon, so they look like artefacts (for phylum: 161 of 226 in the declared phylum, 51 in the predicted one).
For flags found in both runs the result is the opposite (361 of 432 in the predicted phylum, 41 in the declared one, in a random sample of 1,500).
Leaving sequences with a clearly wrong label in the tree therefore creates flags on other sequences that are mostly wrong.

raxtax's own flags are not all right.
Of the 7,174 that can be placed, 1,845 are not flagged by SATIVA.
Only 468 of these have a strong NCBI hit, and for 376 of them the hit lies in the declared genus, for 37 in the genus raxtax proposed.

The checks have limits.
Most of the sequences, 1,348 of the 1,845 and 1,644 of the 3,622, have only weak hits and could not be judged.
The 2,575 flags found only with raxtax, and the 5,329 that SATIVA confirms, were not checked against NCBI.
Keep the prefilter on unless there is a reason to test without it.

## Which value to use

Neither value is better in general.
The choice is between two kinds of error, and which one matters more depends on what the result is used for:

- At `1.0`, more genus- and species-level mislabels are found, but many phylum-level flags are artefacts, so correctly labelled sequences are removed.
- At `0.97`, fewer phylum-level flags are artefacts, so more correctly labelled sequences stay, but about half of the genus- and species-level mislabels are not found and those sequences stay with the wrong label.

If correct labels at genus and species level matter most, do not lower `--cluster_identity`.
If keeping correctly labelled sequences matters more, and missed genus- and species-level mislabels are acceptable, a lower value is reasonable.
The reduction in memory and time is a side effect of that choice, not the reason for it.
