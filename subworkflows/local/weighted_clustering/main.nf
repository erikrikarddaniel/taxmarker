/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WEIGHTED_CLUSTERING - reduce a large input sequence set before alignment/placement

    Design: nf-core/taxmarker#15. A generic per-sequence weight (sequence_id<TAB>weight,
    defaulting to 1 for every sequence if --sequence_weights isn't given -- the
    multiplicative identity, degrading gracefully to "pick the longest sequence per
    taxon") plus VSEARCH clustering by similarity.

    Workflow:
      1. Strip gap characters (caller doesn't guarantee unaligned input --
         ENSURE_ALIGNED, which detects aligned-vs-not, runs later), then
         apply the min_weight cutoff -- absolute exclusion, before
         clustering (saves clustering compute on sequences that would be
         dropped anyway). Cutoff is a no-op if --min_weight isn't set. (WEIGHTFILTER)
      2. Cluster by similarity, at --cluster_identity (default 1.0,
         pure dereplication -- lower it for more aggressive reduction). (VSEARCH_CLUSTER)
      3. Per (cluster, taxon) pair, pick the representative that
         maximises (length / max-length-in-cluster) x weight.          (CLUSTERSELECT)

    Downstream (raxtax, alignment, placement) sees representatives only -- that's the
    actual point of clustering early. Runs before RAXTAX_PREFILTER, so the raxtax
    prefilter gets the same input-size reduction for free.
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { WEIGHTFILTER    } from '../../../modules/local/weightfilter/main'
include { VSEARCH_CLUSTER } from '../../../modules/nf-core/vsearch/cluster/main'
include { CLUSTERSELECT   } from '../../../modules/local/clusterselect/main'

workflow WEIGHTED_CLUSTERING {

    take:
    ch_taxonomy       // channel: taxonomy file (seq_name<TAB>rank1;rank2;...)
    ch_sequences      // channel: unaligned sequences file, already normalised to FASTA by the caller
    sequence_weights  // value:   path to a two-column weight table, or null/empty if not supplied
    min_weight        // value:   absolute weight cutoff, or null/empty to skip it
    cluster_identity  // value:   VSEARCH clustering identity (0-1)

    main:
    def ch_meta_taxonomy  = ch_taxonomy.map  { [ [ id: 'user-alignment' ], it ] }
    def ch_meta_sequences = ch_sequences.map { [ [ id: 'user-alignment' ], it ] }

    // sequence_weights/min_weight are plain values, known before execution starts, so
    // it's safe to resolve/branch on them here at compose time and close over the
    // result inside .map() below, rather than through a channel .combine() -- combine()
    // would silently flatten an empty-list [] value into zero tuple elements instead of
    // one (same pitfall RESOLVETAXONOMY's own optional-taxonomy handling documents).
    def weights_file = sequence_weights ? file(sequence_weights, checkIfExists: true) : []

    // WEIGHTFILTER always runs -- it's also where gap characters get stripped, which
    // every sequence needs before VSEARCH_CLUSTER regardless of whether a cutoff is
    // active. -Infinity keeps a real weight >= it always, making the cutoff itself a
    // true no-op when --min_weight isn't set.
    def effective_min_weight = (min_weight != null && min_weight.toString() != '') ? min_weight : Double.NEGATIVE_INFINITY
    WEIGHTFILTER(
        ch_meta_taxonomy.join(ch_meta_sequences)
            .map { meta, tax, seq -> [ meta, tax, seq, weights_file, effective_min_weight ] }
    )

    // Cluster on the ungapped copy (VSEARCH needs plain sequences); CLUSTERSELECT
    // reads the original (still gapped, if it was) sequences, so already-aligned
    // input still looks aligned to ENSURE_ALIGNED once representatives are picked.
    VSEARCH_CLUSTER(WEIGHTFILTER.out.ungapped_sequences)

    CLUSTERSELECT(
        WEIGHTFILTER.out.taxonomy
            .join(WEIGHTFILTER.out.sequences)
            .join(VSEARCH_CLUSTER.out.uc)
            .map { meta, tax, seq, uc -> [ meta, tax, seq, uc, weights_file ] }
    )

    emit:
    taxonomy  = CLUSTERSELECT.out.taxonomy.map  { _meta, tax -> tax } // channel: taxonomy file, representatives only
    sequences = CLUSTERSELECT.out.sequences.map { _meta, seq -> seq } // channel: sequences file, representatives only
}
