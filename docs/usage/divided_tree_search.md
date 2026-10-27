# nf-core/taxmarker: Divided tree search for large inputs

The reference tree search with RAxML-NG is the step that decides whether a large input can be run at all.
The time grows faster than the number of sequences, and the first step of the whole-tree search, the parsimony starting tree, runs on one core.
`--run_divided_tree_search` cuts the search into parts that run in parallel and joins the results into one tree.

## When to use it

Use it when the whole-tree search is too slow, from some thousands of sequences upwards.
On a random subsample of 20,000 bacterial 16S sequences from GTDB, searched with 8 cores, `--raxmlng_fast` and a fixed model, the whole-tree search took 22,947 s and the divided search 434 s.
On 239,806 sequences the whole-tree search was cancelled after about 30 hours, still in the parsimony starting tree.
The divided search finished, in 472 parts.

At 20,000 sequences the log-likelihood of the divided tree was 0.03% higher than that of the whole-tree search.
The flags of a divided tree were not compared with the flags of a whole-tree search, because no whole-tree search finishes at the sizes where the divided search is needed.

## How it works

1. The taxonomy is cut bottom-up into parts of at most `--tree_part_max_tips` sequences.
   A part that is closed is represented in the part above it by `--tree_part_reps` sequences, so the top part is never larger than the limit either.
2. Each part is searched on its own, under its part of the taxonomy constraint, together with `--tree_part_outgroups` sequences from neighbouring parts that root it.
   The parts run as separate jobs.
3. The part trees are grafted into the top tree.
   The pipeline checks that no taxon of the taxonomy is broken.
4. One RAxML-NG evaluation of the full tree gives its branch lengths and model parameters.

The result has the same form as the whole-tree search, so the leave-one-out placement and everything after it are unchanged.
The part trees are not published, only the final tree and its model.
The search is reproducible: the same input, parameters and `--raxmlng_seed` give the same tree.

## Parameters

| Parameter                   | Default | Meaning                                                                                                            |
| --------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------ |
| `--run_divided_tree_search` | `false` | Search the reference trees in parts.                                                                               |
| `--tree_part_max_tips`      | 2000    | Largest number of sequences in a part.                                                                             |
| `--tree_part_min_tips`      | 10      | Smallest taxon that is searched as a part of its own, unless a node cannot otherwise be brought down to the limit. |
| `--tree_part_reps`          | 3       | Sequences that represent a closed part in the part above it.                                                       |
| `--tree_part_outgroups`     | 4       | Outgroup sequences added to each part.                                                                             |

The defaults worked for 239,806 bacterial sequences.
Change them only if the parts turn out too large for the memory or time of one job.

## Needs a fixed model

The parts cannot select a model each, so `--run_divided_tree_search` needs one named with `--raxmlng_model`, for example `--raxmlng_model GTR+G4`.
With `--run_reference` it needs `--raxmlng_reference_model` as well, or the reference tree uses the model of `--raxmlng_model`.
The pipeline stops with an error at the start if a model would be selected.
See [Reference tree model](../usage.md#reference-tree-model).
If you do not know which model to use, run RAxML-NG's model selection on a subsample first and pass the model it picks.

## Resources

A part has at most `--tree_part_max_tips` sequences.
A part of 1,844 sequences took 4 threads and 170 MiB of memory.
The final evaluation holds the likelihood vectors of the full tree and needed 19 GB at 239,806 sequences.
The pipeline asks for 40 GB for it.

`--run_divided_tree_search` also applies to the reference tree of `--run_reference`, which is searched on one sequence per species and can be large too.
