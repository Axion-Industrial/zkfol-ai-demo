# Text extracted from `fol-zinc.pdf`

This file is generated from the supplied PDF with `pdftotext -layout`. It is included for quick text search and orientation only; the authoritative paper file is `fol-zinc.pdf`.

```text
                                                zk-SNARKs for First Order Logic
                              Murdoch J. Gabbay∗∗                                                                   Andrew Mendelsohn†
                              Heriot-Watt University                                                                 Imperial College London
                            Edinburgh, United Kingdom                                                                London, United Kingdom
                               m.gabbay@hw.ac.uk                                                                        am3518@ic.ac.uk

Abstract                                                                                           Our FOL arithmetisation generalises a previous univariate poly-
We efficiently arithmetise first order logic (FOL) to zk-SNARK-                                 nomial semantics of [15] to a generic semantics parameterised by
friendly relations. FOL is a highly expressive and widely-used math-                            tuples of functions (F in the mathematics below) satisfying some
ematical logic capable (amongst other things) of expressing Turing-                             compatibility properties. We instantiate this semantics with integer
complete computational systems. We provide a framework for arith-                               multilinear polynomials, obtaining a sound-and-complete bridge
metising FOL by extending a univariate polynomial semantics for                                 from range-checked FOL validity over finite models, to polynomial
FOL (J. of Applied Logics ’25) to a general semantics parameterised                             constraints compatible with Zinc.
by a chosen tuple of functions satisfying some compatibility prop-                                 We will now explain what FOL, zk-SNARKs, and Zinc are, and
erties. We instantiate this framework with multilinear polynomials                              how they fit together.
having integer coefficients, for their cryptographic utility. Validity                             FOL. First-order logic is a powerful mathematical logic [5, 13]
judgements in the resulting semantics amount to a combination                                   which more than suffices to specify computation (including Turing-
of range checks and polynomial constraints on the inputs, which                                 complete computation) and correctness properties thereof. Think:
fit tidily into the algebraic indexed relations of Zinc (Crypto ’25).                           “Function 𝑓 computes the square root” or “Abstract machine 𝐴, when
By compiling a suitable polynomial interactive oracle proof with                                given input 𝑥, returns output 𝑓 (𝑥)” or “Transaction 𝑡 is valid ac-
the polynomial commitment scheme ‘Zip’ (cf. Zinc), we obtain a                                  cording to the rules of the system” or “Proposed state-change 𝑆 is
zk-SNARK for relations expressed in FOL. Our arithemetisation                                   compliant with legal requirement 𝑍 ”, etc.
runs over the integers, obviating the need for a (costly) final step                               FOL is sound and complete for a simple and well-studied model-
of converting the initial relations into finite field-based relations.                          theory based on sets and functions. Its notion of truth is simple too,
                                                                                                based on two-valued (i.e. Boolean) truth-tables.
CCS Concepts                                                                                       Thus we can use FOL to simply and cleanly specify a logical
• Theory of computation → Interactive proof systems; Cryp-                                      or computational system and to state correctness properties of its
tographic protocols; Logic and verification; • Security and pri-                                behaviour.1
vacy → Privacy-preserving protocols; Information-theoretic tech-                                   However, FOL has no native cryptographic content: its native
niques; • Mathematics of computing → Probabilistic algorithms.                                  truth-theoretic notions of universal and existential quantification,
                                                                                                ∀𝑥 .𝜙 (𝑥) and ∃𝑥 .𝜙 (𝑥), for example, simply mean ‘check 𝜙 (𝑥) for
Keywords                                                                                        every 𝑥’ and ‘check possible 𝑥 until we find one such that 𝜙 (𝑥)’.
zk-SNARKs, zero knowledge, first order logic, arithmetisation                                       zk-SNARKs. A zk-SNARK is a cryptographic tool to allow a
This authors’ draft was compiled on June 18, 2026.                                              prover to convince a verifier that the prover knows a witness 𝑤
ACM Reference Format:                                                                           such that (𝑥, 𝑤) ∈ R for some relation R and instance 𝑥, succinctly
Murdoch J. Gabbay and Andrew Mendelsohn. 2018. zk-SNARKs for First                              (i.e. requiring minimal work from the verifier), and in zero knowl-
Order Logic. In Proceedings of Make sure to enter the correct conference title                  edge (i.e. the verifier does not learn information about the witness
from your rights confirmation email (Conference acronym ’XX). ACM, New                          𝑤).
York, NY, USA, 13 pages. https://doi.org/XXXXXXX.XXXXXXX                                            (Note that the logical content here is minimal: just an arbitrary
                                                                                                relation R. The focus here is on the cryptographic content. So even
1     Introduction                                                                              at this point, the reader can see where we are heading: we will marry
In this work we give a compositional arithmetisation of first order                             the logical expressivity of FOL with the cryptographic efficiency of
logic (FOL) to zk-SNARK-friendly relations for Zinc [18].                                       zk-SNARKs, using Zinc. But we anticipate. . . )
                                                                                                    Most zk-SNARKs work over a fixed finite field, determined by
∗ Both authors contributed equally to this research.
                                                                                                some prime power 𝑞 = 𝑝 𝑟 (e.g. [20, 16, 12]). Using finite field arith-
                                                                                                metic allows instance-witness pairs in NP relations to be efficiently
Permission to make digital or hard copies of all or part of this work for personal or           (i.e. fast prover run time) and succinctly (i.e. compact proof size)
classroom use is granted without fee provided that copies are not made or distributed
for profit or commercial advantage and that copies bear this notice and the full citation       checked for validity. A common three-step modular framework has
on the first page. Copyrights for components of this work owned by others than the              been developed for constructing zk-SNARKs:
author(s) must be honored. Abstracting with credit is permitted. To copy otherwise, or
republish, to post on servers or to redistribute to lists, requires prior specific permission      (1) Build a polynomial interactive oracle proof (PIOP).
and/or a fee. Request permissions from permissions@acm.org.
Conference acronym ’XX, Woodstock, NY                                                           1 Actually, FOL is a family of logics: there is FOL with equality, FOL with function-
© 2018 Copyright held by the owner/author(s). Publication rights licensed to ACM.               symbols, FOL with reification, FOL with pattern-matching, and so on. We see no
ACM ISBN 978-1-4503-XXXX-X/2018/06                                                              inherent barriers to adapting the FOL language of this paper with extra bells and
https://doi.org/XXXXXXX.XXXXXXX                                                                 whistles.
Conference acronym ’XX, June 03–05, 2018, Woodstock, NY                                                          Murdoch J. Gabbay and Andrew Mendelsohn


   (2) Build a polynomial commitment scheme (PCS).                        just as the FOL-to-integer-polynomials translation from [15] was
   (3) Compile the PIOP+PCS to a zk-SNARK via the transform               being introduced, the integer-multilinear-polynomial-to-zk-SNARK
       of [6, 9].                                                         framework Zinc was also being introduced.
The PIOP is an information theoretic component, and the PCS pro-              We may therefore replace the univariate FOL semantics of [15]
vides cryptographic guarantees of the security of the construction.       with a multivariate semantics, instantiating the general semantics
An overview of the construction may be found in [25, Section 9]           referred to in the first paragraph of this introduction with a set
and a study of its cryptographic properties in [22].                      F of multilinear interpolating polynomials of integer witness vec-
                                                                          tors. While we could choose any set of functions satisfying the
    The wrinkle. A common problem in the real-world use of zk-            necessary compatibility properties for our general semantics, not
SNARKs is that we often want to prove things that are not naturally       only functions that are interpolant polynomials, we choose mul-
expressed by relations R defined by means of arithmetic over finite       tilinear polynomials with integer coefficients, long used for their
fields, much less by arithmetic over a single fixed finite field.         cryptographic utility in building PCS [32], for compatibility with
    To compensate, a so-called arithmetisation pre-processing step        Zinc. Validity judgements in the resulting semantics (Definition 3.1)
is required, which transforms the R that we actually want to prove,       then amount to a combination of range checks and polynomial
into some suitably equivalent ‘zk-SNARK friendly’ R ′ , which is over     constraints on the inputs (Corollary 3.9) which fit into the algebraic
a finite field and thus more amenable to the technical requirements       indexed relations of [18].
of zk-SNARKs.                                                                 Via the polynomial interactive oracle proof (PIOP) plus poly-
    The zk-SNARK friendly R ′ is typically defined by a polyno-           nomial commitment scheme (PCS) framework [6, 9], from any
mial expression, which may then be rewritten to an even more              compatible PIOP and Zip [18, Section 5] we obtain a zk-SNARK
zk-SNARK friendly instance of a constraint system, such as R1CS           for statements expressed in FOL (Corollary 4.4). Since Zinc is a
or CCS [28]. We then run the zk-SNARK on the resulting system of          hash-based zk-SNARK, our construction inherits some degree of
constraints.                                                              plausible post-quantum security.
    For instance: we may want to prove knowledge of the result of
a computation which was performed over the rationals Q (which                 Technical map of the paper. A FOL syntax is given in Figure 1. An
is not a finite field), or over a ring which is not a field, such as      integer semantics ⟨·⟩𝜍𝑥 is given in Figure 3. Note that terms evaluate
Z/𝑛Z for composite 𝑛. Converting these ‘natural’ relations and            to possibly negative integers, but predicates (and range checks)
constraints determined by such computations into constraints over         evaluate to natural numbers (Lemma 2.17). The integer semantics
finite fields can be computationally expensive to perform, as well        is sound and complete by Theorem 2.19.
as causing a significant increase in the instance size upon which a           We then consider an alternative compilation chain: a compilation
zk-SNARK is run, resulting in a costlier proof. This motivates the        ⟨·⟩ of FOL syntax to a novel notion of enriched polynomial is in Fig-
study of techniques to avoid or reduce the burden of arithmetisation      ure 2; a compilation mkQ𝑥F of enriched polynomials to multivariate
overheads.                                                                polynomials is in Figure 4; and an evaluation from multivariate
                                                                          polynomials to integers is in Definition 3.6. Equivalence of this
    Zinc. Zinc [18] attempts to ameliorate the cost of arithmetisation.   chain with the integer semantics is our central technical result in
It does not make it go away, but it pushes development effort away        Theorem 3.8. As per Corollary 3.9, FOL validity2 is equivalent to a
from the programmer and onto the cryptographic back-end.                  relation determined by polynomial equalities, so that we obtain a
    In particular, Zinc gives a PIOP for relations defined over the       zk-SNARK for FOL in Section 4.
integers Z, together with a PCS dubbed ‘Zip’, which compile to
yield a zk-SNARK.                                                             Examples. We include two examples of computation in Section 5:
    Zinc allows for succinct proofs of relations with mixed character-    exponentiation and SK combinator reduction. Both are toy exam-
istic, over numerous rings, to be provided by a prover. The concept       ples, of course, but they still matter.
is quite simple (the devil is in the detail of making it work): for           Exponentiation is a mathematical function and it is there to
well-chosen parameters, we just sample some random primes (up             illustrate that we can define mathematical functions. It should be
to some bound) and run a finite field zk-SNARK on the relation            clear that other, more elaborate functions would just require writing
instances modulo the sampled primes, with a low resulting sound-          other, more elaborate FOL definitions.
ness error. This removes the need to arithmetise such instances,              SK combinators may be a toy, but they are the opposite of trivial.
beyond reducing modulo primes. We note the relations in Zinc are          This is a powerful and mathematically convenient Turing-complete
defined on multilinear polynomials with integer coefficients.             computational model. Haskell can be compiled to SK combinators
                                                                          directly [4]3 and only slightly more complex combinatory systems
    Full circle back to FOL. Previous work [15] shows how to trans-       are used as practical compilation targets for industrial program-
late FOL to polynomials with integer coefficients, such that the          ming languages (a clean example is Nock [31]). Combinators admit
standard FOL truth-table-and-sets-based notion of validity may be         a particularly compact expression in FOL, so the import of our ex-
equivalently (i.e. soundly and completely) expressed using poly-          amples is that we can arithmetise logical assertions (by definition;
nomial root tests: a certain polynomial ⟨𝜙⟩ corresponding to the          FOL is a logic), functions, and programs, covering (albeit in toy
predicate 𝜙 has roots over a certain set if and only if that predicate
is true in its standard FOL semantics.                                    2 More precisely: a notion of validity for range-checked FOL predicates. Details in the
    However, [15] did not explicitly connect the resulting integer        body of the paper.
polynomials to a cryptographic backend. In a happy coincidence,           3 The compilation is to SKI, but the I combinator can be expressed using S and K.
zk-SNARKs for First Order Logic                                                                        Conference acronym ’XX, June 03–05, 2018, Woodstock, NY


form) all the major food groups of logic and computation, so to                   2.1    Multilinear Polynomials
speak.                                                                               Definition 2.4. A multilinear polynomial over a ring R is
                                                                                                                          Í<∞ Î𝜇           𝑒
                                                                                  a multivariate polynomial 𝑓 (X) = 𝑖=1         𝑎𝑖 𝑗=1 𝑋 𝑗 𝑖 𝑗 in finitely
   Related work on arithmetisation. Other recent works have sought                many variables X = (𝑋 1, . . . , 𝑋 𝜇 ) with coefficients 𝑎𝑖 ∈ R, such
to address the problems of arithmetisation. Prior to Zinc, [10] aimed             that no variable occurs in any homogeneous component with mul-
to build a zk-SNARK for integer relations. However, they relied                   tiplicity larger than one; that is, 0 ≤ 𝑒𝑖 𝑗 ≤ 1 for all 𝑖 and for all
on the so-called Hidden Order Groups assumption, which does not
                                                                                  𝑗 ∈ [𝜇]. Write R !! [X] for the set of multilinear polynomials in X
provide post-quantum security. There are also ‘field-agnostic’ zk-
                                                                                  with coefficients in R.
SNARKs, which can prove validity of instances of relations defined
over any finite field [19, 28, 8, 36]. However, these schemes could                  Definition 2.5. Given a function 𝑓 : {0, 1} 𝜇 → R and a list of 𝜇
not handle the setting of infinite fields or integral domains which               variables X, define 𝑓˜ ∈ R !! [X], the multilinear extension (MLE)
are not fields. There are also schemes targeting relations over finite            of 𝑓 , by
rings which are not fields, e.g. [17, 33, 34]. In a different direction,                                              Í
[21, 2] designed tools (‘Distiller’, ‘Reef’) which reduce the number                           𝑓˜(𝑋 1, . . . , 𝑋 𝜇 ) = 𝑦 ∈ {0,1} 𝜇 𝑓 (𝑦) · eq(𝑦, X)
                                                                                                                      Î𝜇
of constraints required to provide a proof of the original computa-                         where eq(𝑦, X) = 𝑖=1 (𝑦𝑖 𝑋𝑖 + (1−𝑦𝑖 )(1−𝑋𝑖 ))
tion. Such methods could be used concurrently with our work here.
Similarly [26] is concerned with reducing the amount of ‘foreign                  This is the unique multilinear polynomial in R !! [X] which agrees
field’ arithmetic required in proof systems. Akin to our application              with 𝑓 on the 𝜇-hypercube, by which we mean that 𝑓 (𝑦) = 𝑓˜(𝑦)
to SK combinators, [7, 27] design zk-SNARKs targeting computa-                    for every 𝑦 ∈ {0, 1} 𝜇 [30].
tions performed in a specific programming language, in their case
                                                                                     Definition 2.6. Given a vector v = (v0, . . . , v2𝜇 −1 ) ∈ R 2 , let
                                                                                                                                                         𝜇
in C.
                                                                                  𝑓v : {0, 1} 𝜇 → R take 𝑥 to 𝑓v (𝑥) = vb2int (𝑥 ) , where we identify 𝑥-
   See [23] for an introduction to zk-SNARKs.
                                                                                  the-binary-string with the b2int (𝑥)-th entry of v. E.g. 𝑓v (101) = v5 .
                                                                                  Define the multilinear extension of v, 𝑓˜v , to be the multilinear
2     Basic definitions                                                           extension of 𝑓v .
We begin with some notation:
                                                                                  2.2    zk-SNARKs and Algebraic Indexed Relations
    Notation 2.1. (1) Z = {. . . , -2, -1, 0, 1, 2, . . . } is the integers and   A zk-SNARK is a complete succinct non-interactive argument of
N = {0, 1, 2, . . . } is the non-negative integers and Q is the ratio-            knowledge satisfying knowledge soundness (up to some error 𝜀),
nal numbers. (2) Given 𝑛 ∈ N write [𝑛] for {1, . . . , 𝑛}. (3) Write              allowing a prover to convince a verifier of knowledge of a witness
indexed NP relations as REL = {( i, x, w)}. For any relation REL,                 satisfying an instance of some relation REL = RELgp , parameterised
let L (REL) = {( i, x) | ∃w : ( i, x, w) ∈ REL} denote the language               by global parameters gp.
corresponding to REL. (4) Write R 𝜕 for elements of a ring R of bit-                 We now explain these terms in more detail. Since we will obtain
length less than or equal to some bound 𝜕 > 0. (5) Write M𝑛×𝑚 (R)                 a zk-SNARK by composing a transformation from FOL to algebraic
for a matrix ring over R of dimension 𝑛 × 𝑚. (6) Write 𝑀 @𝑖,𝑗 for                 indexed relations (Definition 2.9) compatible with Zinc-PIOP [18],
the 𝑗th element of the 𝑖th row of a matrix 𝑀. (7) We distinguish                  and then applying the transform of [6, 9] on Zinc-PIOP with the
operating symbols for logical objects from mathematical operations                PCS Zip [18, Section 5], we borrow the following definition of
by using = , < , etc. rather than =, <, etc. for operations in first order        interactive proofs:
logic. (8) We use [[·]] to denote an oracle to a string or polynomial
written within the brackets. (9) Write π𝜈 for the projection taking                  Definition 2.7 ([18, Definition 3.2]). An Interactive Proof (IP)
a vector of length 𝜇 ≥ 𝜈 to its 𝜈th element. Thus π𝜈 (𝑣 1, ..., 𝑣 𝜇 ) = 𝑣 𝜈 .     for a relation RELgp with global parameters gp is a triple of algo-
(10) Given some boolean assertion Φ (i.e. some mathematical claim                 rithms (Ind, P, V), where for all ( i, x, w) ∈ RELgp , Ind is a deter-
that is either true or false), define 𝜹 (Φ) the indicator of Φ such               ministic algorithm taking (gp, i) as input and outputting verifier
that 𝜹 (Φ) = 0 when the assertion Φ is true, and 𝜹 (Φ) = 1 when Φ                 and prover parameters (vp, pp) ← Ind(gp, i). The pair (P, V) =
is false (pun on the Dirac 𝜹 function). (11) We may write function                (P(pp, x, w), V(vp, x)) is a pair of interactive algorithms with in-
application as 𝑓 (𝑥) or as 𝑓 𝑥. We will use whichever notation seems              teraction denoted ⟨P, V⟩. An IP may satisfy
clearest; meaning will always be clear.                                              (1) Completeness with completeness error 𝜀 comp : for all ( i, x, w) ∈
                                                                                         RELgp ,
    Definition 2.2.     (1) Given a string 𝑠 = (𝑠 1, 𝑠 2, . . . , 𝑠 𝜇 ), define
                                                                                        Pr [⟨P(pp, x, w), V(vp, x)⟩ = 1 | (vp, pp) ← Ind(gp, i)]
        b2int (𝑠) = 1≤𝜈 ≤𝜇 𝑠 𝜈 · 2𝜈 −1 .
                     Í
        In this paper, either 𝑠 will be a string of binary digits (so                                                          ≥ 1 − 𝜀 comp (gp, i, x)
        b2int (𝑠) is an integer) or a string of variable symbols (so                 (2) Soundness with soundness error 𝜀 sound : for any unbounded
        b2int (𝑠) is a multivariate polynomial).                                         adversarial prover P∗ and for any (i, x), we have:
    (2) Given 𝑖∈N, write ∅b (𝑖) for the binary decomposition of 𝑖.
                                                                                           ⟨P∗ (pp, i, x), V(vp, x)⟩ = 1 (vp, pp) ← Ind(gp, i)
                                                                                                                                                   
                                                                                      Pr
   Lemma 2.3. If 𝑥 ∈ N then ∅b (𝑥) is the unique string of binary                             ∧( i, x) ∉ L RELgp
digits such that b2int ( ∅b (𝑥)) = 𝑥.                                                                                            ≤ 𝜀 sound (gp, i, x)
Conference acronym ’XX, June 03–05, 2018, Woodstock, NY                                                                      Murdoch J. Gabbay and Andrew Mendelsohn


   (3) Knowledge soundness with knowledge soundness error 𝜀 ks :                  Summing this up in symbols, RELgp,R,Q has the following form:
       there exists a probabilistic extractor Ext such that, given
       oracle access to any unbounded adversarial prover P∗ and                                
                                                                                               
                                                                                                                gp = (𝑘, 𝑚, 𝑛, 𝜇, 𝜕),                                              
                                                                                                                                                                                    
                                                                                                                                                                                    
                                                                                                                 i = ( [[𝑔1 ]], . . . , [[𝑔𝑛 ]]) ,
                                                                                               
                                                                                                                                                                                   
                                                                                                                                                                                    
       any ( i, x), we have:
                                                                                               
                                                                                                                                                                                   
                                                                                                                                                                                    
                                                                                                                 x = ([[𝑓1 ]], . . . , [[𝑓𝑘 ]], y) for some y ∈ R𝑚
                                                                                                                                                                                   
                                                                                                                                                                 𝜕,
                                                                                               
                                                                                                                                                                                   
                                                                                                                                                                                    
                                                                                                                 w = (f1 , . . . , f𝑘 ) ∈ (R 𝜕
                                                                                                                                                                                   
         ⟨P∗ (pp, i, x), V(vp, x)⟩ = 1 (vp, pp) ← Ind(gp, i)
                                                                                             
                                                                                                                                                !! [X])𝑘 ,                         
                                                                                                                                                                                    
                                                                                   RELgp,R,Q =   ( i, x, w)                                                                             (1)
                                                                                                                                           !!
                                                                                                                 (𝑔1, . . . , 𝑔𝑛 ) ∈ (R 𝜕 [X])     𝑛
    Pr                                                                                         
                                                                                                                                                                                   
                                                                                                                                                                                    
              ∧( i, x, w) ∉ RELgp      w ← ExtP∗ (gp, i, x)
                                                                                               
                                                                                                                                                                                  
                                                                                                                                                                                    
                                                                                                                 𝑄 (𝑔1 (x), . . . , 𝑔𝑛 (x), f1 (x), . . . , f𝑘 (x)) x∈ {0,1} 𝜇 , y 
                                                                                               
                                                                                                                                                                                   
                                                                                               
                                                                                                                                                                                   
                                                                                                                                                                                    
                                             ≤ 𝜀 ks (gp, i, x, 𝜀 P∗ )
                                                                                               
                                                                                                                                                                                   
                                                                                                                                                                                    
                                                                                               
                                                                                                                    = 0, for all 𝑄 ∈ Q                                             
                                                                                                                                                                                    
       where                                                                        Remark 2.10. We can express CCS (an expressive constraint sys-
                                          P∗ (gp, i, x), V(vp, x) = 1             tem) via Definition 2.9 [18, Section 4.4]. We can also express range
                                                                             
        𝜀 P∗ = 𝜀 P∗ (gp, i, x) = Pr
       is the probability that P∗ (gp, i, x) convinces V(vp, x).                  check/lookup relations [28], defined by

   This allows us to introduce (polynomial) interactive oracle proofs:                          
                                                                                                
                                                                                                                      gp = (1, 0, 1, log 𝑛𝑎 + log 𝑛𝑡 , 𝜕) ,                            
                                                                                                                                                                                        
                                                                                                                                                                                        
                                                                                                                       i = ([[𝑡]]),
                                                                                                                                                                                       
     Definition 2.8 ([18, Definitions 3.3, 3.4]). An interactive oracle
                                                                                                
                                                                                                                                                                                       
                                                                                                                                                                                        
                                                                                                                                                                                       
                                                                                                                       x = ( [[𝑎]]),
                                                                                                
                                                                                                                                                                                       
                                                                                                                                                                                        
proof (IOP) is an interactive proof for an indexed relation RELgp =
                                                                                                
                                                                                                                                                                                       
                                                                                                                                                                                        
                                                                                                                       w = (𝑎(X)),
                                                                                                
                                                                                                                                                                                       
                                                                                                                                                                                        
                                                                                                                                                                                       
( i, x, w) in which i and x may contain oracles to strings of elements            Lookgp,R =
                                                                                                
                                                                                                
                                                                                                    ( i, x, w)
                                                                                                                                                                                      
                                                                                                                                                                                        
                                                                                                                      𝑎(X) ∈ R 𝜕!! [X], X = 𝑋 1, . . . , 𝑋 log 𝑛𝑎 ,
from a ring R.                                                                                  
                                                                                                
                                                                                                                                                                                     
                                                                                                                                                                                        
                                                                                                                                                                                        
     The full strings behind the oracles from i and x are contained                                                   𝑡 (Y) ∈ R 𝜕!! [Y], Y = 𝑌1, . . . , 𝑌log 𝑛𝑡 ,
                                                                                                
                                                                                                                                                                                       
                                                                                                                                                                                        
                                                                                                
                                                                                                                                                                                       
                                                                                                                                                                                        
                                                                                                                                                                                       
in the prover’s parameters pp and in the witness w, respectively.
                                                                                                                      
                                                                                                                        𝑎(x) | x ∈ {0, 1}log 𝑛𝑎
                                                                                                
                                                                                                                                                                                       
                                                                                                                                                                                        
                                                                                                
                                                                                                                                                                                       
                                                                                                                                                                                        
                                                                                                                                                                                       
In every protocol message, the prover P sends oracles to strings of                             
                                                                                                                           ⊆ 𝑡 (y) | y ∈ {0, 1}log 𝑛𝑡                                  
                                                                                                                                                                                        
elements from R. In every round, the verifier V sends a random
challenge 𝜌𝑖 .                                                                    as AIRs as follows:
     A polynomial interactive oracle proof (PIOP) over a ring                        Let 𝑎(X) and 𝑡 (Y) be multilinear polynomials on log 𝑛𝑎 and
R is an IOP such that all oracles contain polynomials with coeffi-                log 𝑛𝑡 variables respectively, and let a and t be the vectors of evalu-
cients in R of prescribed number of variables 𝜇 and degrees. These                ations of 𝑎(X) and 𝑡 (Y) on the hypercubes a = (𝑎(X)) {0,1}𝑛𝑎 and
polynomials can be queried at any point of R 𝜇 .                                  t = (𝑡 (Y)) {0,1}𝑛𝑡 , respectively. Define variables
                                                                                                                                
   Zinc [18] develops a PIOP for multilinear relations defined on Q,                            W = ( (𝑊x ) x∈ {0,1} log 𝑛𝑎 , 𝑊y y∈ {0,1} log 𝑛𝑡 )
where inputs are restricted to have bounded bit-length 𝜕 = poly(𝜆)
in the security parameter 𝜆. Here the bit-length of a rational number             and polynomials
is computed by writing the rational number as a fraction in lowest                          n                           Ö                                        o
                                                                                                                                             
terms, then computing the base-2 representations of the numerator                   QLook = 𝑄 x (W) :=                                𝑊x − 𝑊y | x ∈ {0, 1}log 𝑛𝑎
and denominator (padding the smaller of the two so that they are                                                 y∈ {0,1} log 𝑛𝑡
of equal bit-size), and concatenating. This representation gives a
bit-length of at most 2(log |𝑎| + log 𝑏) + 3, where an extra bit has              Then
been added to account for sign.                                                                                             gp = (1, 0, 1, log 𝑛𝑎 + log 𝑛𝑡 , 𝜕) ,                
                                                                                                                                                                                 
   Zinc’s relations are defined on the rationals but honest provers                                
                                                                                                   
                                                                                                   
                                                                                                                            i = ( [[𝑡]]),   x = ([[𝑎]]),
                                                                                                                                                                                  
                                                                                                                                                                                  
                                                                                                                                                                                  
                                                                                                                                                                                  
                                                                                                                                                                                 
are expected to use integer inputs. We next formally define the                                    
                                                                                                   
                                                                                                   
                                                                                                                            𝑎(X) ∈ R 𝜕!! [X],           
                                                                                                                                                                                  
                                                                                                                                                                                  
                                                                                                                                                                                  
                                                                                                                                                                                  
relations used by Zinc. We first need some jargon: for the rest of                                 
                                                                                                   
                                                                                                   
                                                                                                                                    X = 𝑋 1, . . . , 𝑋 log 𝑛𝑎 ,
                                                                                                                                                                                  
                                                                                                                                                                                  
                                                                                                                                                                                  
                                                                                                                                                                                  
this section, we fix an integral domain R ⊂ Q, and a tuple of global
                                                                                                   
                                                                                                   
                                                                                                                                                                                 
                                                                                                                                                                                  
                                                                                                                                                                                  
                                                                                   RELgp,R,QLook =   ( i, x, w)              𝑡 (Y) ∈ R 𝜕!![Y],                                     (2)
parameters gp = (𝑘, 𝑚, 𝑛, 𝜇, 𝜕) of integers defining the magnitudes                                                                                                             
                                                                                                                                     Y = 𝑌1, . . . , 𝑌log 𝑛𝑡 ,
                                                                                                   
                                                                                                                                                                                 
                                                                                                                                                                                  
                                                                                                                                                                                 
and dimensions of the objects in Definition 2.9:                                                   
                                                                                                                                                                                 
                                                                                                                                                                                  
                                                                                                                             w = (𝑎(X)),
                                                                                                   
                                                                                                                                                                                 
                                                                                                                                                                                  
                                                                                                                                                                                 
  Definition 2.9. Let Q be a set of multivariate polynomials with
                                                                                                                                                                                 
                                                                                                                             𝑄 x (a, t) = 0,
                                                                                                   
                                                                                                                                                                                 
                                                                                                                                                                                  
                                                                                                   
                                                                                                                                                                                 
                                                                                                                                                                                  
coefficients in a ring R and let X = (𝑋 1, . . . , 𝑋 𝜇 ) denote 𝜇 variables.
                                                                                                                                                                                 
                                                                                                   
                                                                                                                                   for all x ∈ {0, 1}log 𝑛𝑎                      
                                                                                                                                                                                  
An algebraic indexed relation (AIR) [18, Definition 4.1] is a set
RELgp,R,Q of triples ( i, x, w) such that:                                        is equivalent to the (standard) lookup relation Lookgp [18, Sec-
   (1) The index i is an 𝑛-tuple of oracles [[𝑔1 ]], . . . , [[𝑔𝑛 ]] to multi-    tion 4.4].
       linear polynomials 𝑔1, . . . , 𝑔𝑛 ∈ R 𝜕!! [X] for bit-length 𝜕 > 0.           Call an index-instance-witness triple for an algebraic indexed
   (2) The witness w is a 𝑘-tuple of multilinear polynomials with                 relation REL well-formed when it is of the form specified in Defini-
        𝜕-bounded coefficients, f1, . . . , f𝑘 ∈ R 𝜕!! [X].                       tion 2.9. In particular, we assume throughout that malicious provers
   (3) The instance x = ([[𝑓1 ]], . . . , [[𝑓𝑘 ]], y) where y ∈ R𝑚      𝜕 for     and adversaries use well-formed instances of AIRs, and we assume
       some 𝑚 ≥ 0 and the [[𝑓𝑖 ]] are oracles to the elements in w.               that R = Z. We thus remove the subscripted ring in our relation
   (4) Q is a set of multivariate polynomials with coefficients in R              definitions and write RELgp,Q for AIRs.
       in (𝑛 + 𝑘) · 2𝜇 + 𝑚 variables, each of which vanishes (i.e. is                We refer the reader to [18, Definition 3.5] for the definition of
       equal to zero) when evaluated on the values                                a PCS. A multilinear PCS is succinct if it outputs commitments
         ( (𝑔1 (x), . . . , 𝑔𝑛 (x), f1 (x), . . . , f𝑘 (x)) x∈ {0,1} 𝜇 , y)       which are sublinear in 2𝜇 .
zk-SNARKs for First Order Logic                                                                               Conference acronym ’XX, June 03–05, 2018, Woodstock, NY



   Term    𝑡 ::= 𝑞 | 𝑡 + 𝑡 | 𝑡 ∗ 𝑡 | len(C) | reify(𝜙) |                                Lemma 2.14. If 𝑡 ∈ Term and 𝜙 ∈ Pred then ⟨𝑡⟩ and ⟨𝜙⟩ are
                 𝑋 | C𝑖 (𝑋 ) | C𝑖 C 𝑗 (𝑋 )                                           enriched polynomials.
                    (𝑖, 𝑗 ∈ [ar (C)], 𝑞 ∈ Z)
                                                                                        Proof. By a routine induction.                                                   □
   Pred 𝜙,𝜓 ::= 𝑡 = 𝑡 | 𝜙 ∧ 𝜙 | 𝜙 ∨ 𝜙
   RCheck 𝑅 ::= ∅ | 𝑅, 𝑡 < C𝑖 | 𝑅, C𝑖 < 𝑡                                               Remark 2.15. Why are ⟨·⟩ and enriched polynomials interesting?
                    (𝑖 ∈ [ar (C)])                                                      (1) We can map 𝑡 ∈ Term and 𝜙 ∈ Pred (Figure 1) to enriched
   EP     𝑃 ::= 𝑞 | 𝑃+𝑃 | 𝑃∗𝑃 | len(C) | 𝑋 | C𝑖 (𝑋 ) | C𝑖 C 𝑗 (𝑋 )                          polynomials as per Lemma 2.14.
                    (𝑖, 𝑗 ∈ [ar (C)], 𝑞 ∈ Z)                                            (2) We can map enriched polynomials to actual multivariate
                                                                                            polynomials, as per mkQ𝑥F in Figure 4.
Figure 1: Terms, predicates, range checks, and enriched poly-                           (3) We can evaluate the variables in the resulting polynomials
nomials (Definition 2.12(1))                                                                generated by mkQ𝑥F using 𝛽 F (Definition 3.6), such that (by
                                                                                            Theorem 3.8) the composition 𝛽 F ◦ mkQ𝑥F ◦ ⟨·⟩ coincides (by
                                                                                            Theorem 2.19) with the sound and complete integer seman-
2.3      First-order logic                                                                  tics for FOL ⟨·⟩𝜍𝑥 from Figure 3.
We set up the syntax and denotation of a simple first-order logic:                      (4) We can use the above machinery to generate polynomial
                                                                                            relations compatible with Zinc.
   Notation 2.11. Here and for the rest of the paper we fix the
following syntactic data:
                                                                                     2.4      Integer semantics for FOL
    (1) A single matrix variable symbol C ∈ MVS with a fixed
                                                                                     In this section we define ⟨·⟩𝜍𝑥 (Figure 3), describing a sound and
        but arbitrary arity ar (C) ≥ 1. (MVS might contain other
                                                                                     complete integer semantics for FOL.
        symbols, but we will only need one for this paper.)
    (2) A set BVar of quad-indexed variable symbols 𝐵𝑖,𝜈 ∈
                                                            𝑗,𝑥                         Definition 2.16 (FOL semantics).        (1) We define an interpre-
        BVar, where 𝑖, 𝑗, 𝑥, 𝜈 ∈ N.                                                         tation 𝜍 : MVS → Mar (C) ×ℓ𝜍 (C) (N) to map C ∈ MVS to an
    (3) A single index variable symbol 𝑋 .                                                  ar (C) × ℓ𝜍 (C) non-negative integer matrix, where ℓ𝜍 (C) ∈
These are all just formal symbols. We assume they are all distinct.                         N ≥1 depends on 𝜍.6
                                                                                        (2) Suppose 𝑡 ∈ Term and 𝜙 ∈ Pred and 𝑅 ∈ RCheck and
   A sound and complete polynomial semantics for first-order logic                          𝑥 ∈ [ℓ𝜍 (C)] and 𝜍 is an interpretation. Define a semantics
(FOL) from [15] used univariate polynomials and their properties to                         ⟨𝑡⟩𝜍𝑥 ∈ Z, ⟨𝜙⟩𝜍𝑥 , ⟨𝑅⟩𝜍 ∈ N as per Figure 3.
precisely (i.e. soundly and completely) capture the logical content of
FOL predicates.4 We now construct a simplified yet expressive FOL                       Definition 2.16 might seem odd: FOL already has a well-known
syntax (Figure 1) and a version of the semantics in [15] (Figure 3)                  Boolean truth-valued semantics, so: a) why give it an integer se-
which are tailored to our needs in this paper.                                       mantics, and b) what does this integer semantics even mean? We
                                                                                     answer as follows: we give FOL an integer semantics because it
   Definition 2.12.  (1) Define syntaxes of terms, predicates,                       will help us arithmetise FOL in Section 3. As to what the semantics
       and enriched polynomials in Figure 1.                                         means, we can sum this up using two slogans:
   (2) We may write ⊤ as sugar for (0 = 0), and ⊥ for (0 = 1).                          (1) Slogan 1. Zero = true; non-zero = false. We treat N as a
   (3) Define a mapping ⟨·⟩ taking terms and predicates to enriched                         domain of truth-values in which zero is the single designated
       polynomials in Figure 2.                                                             ‘true’ truth-value, and non-zero values are flavours of ‘false’.
    Remark 2.13 (Some comments on Definition 2.12). Pred is a simple                    (2) Slogan 2. Equality = square of difference; conjunction =
predicate language of conjunctions and disjunctions over equalities.                        sum; disjunction = product. This just reads off the relevant
We can express true as 0 = 0 and false as 0 = 1. A quantification                           clauses in Figure 3.
over the index variable symbol 𝑋 is implicit in the syntax, as will                  These slogans are mathematically justified by Lemma 2.17 and
become explicit later in Definition 3.1(3&4) and Lemma 3.2.                          Theorem 2.19.
    Pred only has one index variable symbol 𝑋 , and one polynomial
                                                                                        Lemma 2.17 (Non-negativity). Suppose 𝜙 ∈ Pred and 𝜍 is an
function symbol C. In general we might want more (if only for
                                                                                     interpretation. Then ⟨𝜙⟩𝜍𝑥 ≥ 0.
convenience), but even in its current form Pred is actually very
expressive.5 So Pred may be compact, but it is not a toy: in particular,               Proof. We consider ⟨𝜙⟩𝜍𝑥 in Figure 3: ⟨𝑡 = 𝑡 ′ ⟩𝜍𝑥 is a square and
it can express the full list of examples from [15].
                                                                                     squares are non-negative (even if ⟨𝑡⟩𝜍𝑥 or ⟨𝑡 ′ ⟩𝜍𝑥 are negative); ⟨𝜙∧𝜙 ′ ⟩𝜍𝑥
    Enriched polynomials are just a subsyntax of terms: this is de-
liberate, and we will exploit it below. We do not use examples that                  6 Some words on the design here: Letting 𝜍 (C) be a matrix of non-negative numbers
use reify in this paper but we retain it just to make clearer that                   is convenient because it slightly simplifies b2int and ∅b in Definition 2.2 (no need to
the syntax here is fully as expressive as that of [15] (albeit more                  worry about binary representations of negative numbers). We can still get negative
                                                                                     numbers in terms 𝑡 using addition and multiplication by 𝑞 ∈ Z.
concisely presented).                                                                    Perhaps we should call this a numerical semantics for FOL, but in the context of
                                                                                     cryptography that might be misread as a semantics in finite fields. If this bothers the
4 A cryptographically oriented version is in [14].
                                                                                     reader, they can substitute ‘numerical’ or ‘numbers-based’ every time we write integer,
5 Logicians please note that reify is extremely powerful. This syntax is much more   and no harm will come of it. We will always specify precise types, so meaning will be
expressive than it looks.                                                            clear.
Conference acronym ’XX, June 03–05, 2018, Woodstock, NY                                                                               Murdoch J. Gabbay and Andrew Mendelsohn


                                   ⟨𝑞⟩ = 𝑞 (𝑞 ∈ Z)             ⟨𝑡 + 𝑡 ′ ⟩ = ⟨𝑡⟩ + ⟨𝑡 ′ ⟩         ⟨𝑡 ∗ 𝑡 ′ ⟩ = ⟨𝑡⟩ ∗ ⟨𝑡 ′ ⟩        ⟨len(C)⟩ = len(C)
                                  ⟨𝑋 ⟩ = 𝑋                    ⟨C𝑖 (𝑋 )⟩ = C𝑖 (𝑋 )            ⟨C𝑖 C 𝑗 (𝑋 )⟩ = C𝑖 C 𝑗 (𝑋 )        ⟨reify(𝜙)⟩ = ⟨𝜙⟩

                             ⟨𝑡 = 𝑡 ′ ⟩ = (⟨𝑡⟩−⟨𝑡 ′ ⟩) 2     ⟨𝜙 ∧ 𝜙 ′ ⟩ = ⟨𝜙⟩ + ⟨𝜙 ′ ⟩         ⟨𝜙 ∨ 𝜙 ′ ⟩ = ⟨𝜙⟩ ∗ ⟨𝜙 ′ ⟩

                                  Figure 2: From Term and Pred to enriched polynomials EP (Definition 2.12(3))

                     ⟨𝑞⟩𝜍𝑥 = 𝑞                            ⟨𝑡 + 𝑡 ′ ⟩𝜍𝑥 = ⟨𝑡⟩𝜍𝑥 + ⟨𝑡 ′ ⟩𝜍𝑥       ⟨𝑡 ∗ 𝑡 ′ ⟩𝜍𝑥 = ⟨𝑡⟩𝜍𝑥 ∗ ⟨𝑡 ′ ⟩𝜍𝑥        ⟨len(C)⟩𝜍𝑥 = len(𝜍 (C))
                    ⟨𝑋 ⟩𝜍𝑥 = 𝑥                           ⟨C𝑖 (𝑋 )⟩𝜍𝑥 = 𝜍 (C) @𝑖,𝑥           ⟨C𝑖 C 𝑗 (𝑋 )⟩𝜍𝑥 = 𝜍 (C) @𝑖,𝜍 (C) @𝑗,𝑥    ⟨reify(𝜙)⟩𝜍𝑥 = ⟨𝜙⟩𝜍𝑥

                ⟨𝑡 = 𝑡 ′ ⟩𝜍𝑥 = (⟨𝑡⟩𝜍𝑥 −⟨𝑡 ′ ⟩𝜍𝑥 ) 2     ⟨𝜙 ∧ 𝜙 ′ ⟩𝜍𝑥 = ⟨𝜙⟩𝜍𝑥 + ⟨𝜙 ′ ⟩𝜍𝑥       ⟨𝜙 ∨ 𝜙 ′ ⟩𝜍𝑥 = ⟨𝜙⟩𝜍𝑥 ∗ ⟨𝜙 ′ ⟩𝜍𝑥

                     ⟨∅⟩𝜍 = 0                         ⟨𝑅, C𝑖 < 𝑡⟩𝜍 = ⟨𝑅⟩𝜍 + 𝜹 (∀𝑥 ∈[len(𝜍 (C))]. ⟨𝑡⟩𝜍𝑥 >𝜍 (C) @𝑖,𝑥 )
                                                      ⟨𝑅, 𝑡 < C𝑖 ⟩𝜍 = ⟨𝑅⟩𝜍 + 𝜹 (∀𝑥 ∈[len(𝜍 (C))]. ⟨𝑡⟩𝜍𝑥 <𝜍 (C) @𝑖,𝑥 )
                               Above: 𝜹 is the indicator function from Notation 2.1(10), and @𝑖,𝑥 is from Notation 2.1(6).

                        Figure 3: Integer semantics for FOL terms, predicates, and range checks (Definition 2.16)


is a sum and sums of non-negatives are non-negative; ⟨𝜙 ∨ 𝜙 ′ ⟩𝜍𝑥 is                               (2) Say (𝜙, 𝑅) ∈ Pred × RCheck is range-checked when for
a product and products of non-negatives are non-negative.         □                                    every 𝑗 such that 𝜙 uses C 𝑗 as a pointer, 𝑅 contains conditions
                                                                                                       of the form 0 < C 𝑗 and C 𝑗 < len(C)+1.
   Definition 2.18 (Validity). Suppose 𝜙 ∈ Pred and 𝑅 ∈ RCheck                                     (3) A judgement is a 3-tuple, written C ⊨𝜍 𝜙; 𝑅, of: an interpreta-
and 𝜍 is an interpretation on C and 𝑥 ∈ [len(𝜍 (C))]. Then write                                       tion 𝜍; a predicate 𝜙 ∈ Pred; and a range check 𝑅 ∈ RCheck;
𝑥 ⊨𝜍 𝜙 when ⟨𝜙⟩𝜍𝑥 = 0, and write ⊨𝜍 𝑅 when ⟨𝑅⟩𝜍 = 0.                                                   such that (𝜙, 𝑅) is range-checked.
                                                                                                   (4) Call a judgement C ⊨𝜍 𝜙; 𝑅 valid when: ⟨𝜙⟩𝜍𝑥 = 0 for every
   Theorem 2.19 (Soundness and completeness). Suppose 𝜙, 𝜙 ′ ∈
                                                                                                       𝑥 ∈ [len(𝜍 (C))], and ⟨𝑅⟩𝜍 = 0.
Pred, and 𝑡, 𝑡 ′ ∈ Term, and 𝑅 ∈ RCheck. Suppose 𝜍 is an interpreta-
                                                                                                   (5) We may write C ⊨𝜍 𝜙; ∅ just as C ⊨𝜍 𝜙, and we may write
tion, for brevity write ℓ = len(𝜍 (C)), and suppose 𝑥 ∈ [ℓ]. Then:
                                                                                                       C ⊨𝜍 ⊤ ; 𝑅 just as C ⊨𝜍 𝑅.
    (1) 𝑥 ⊨𝜍 𝑡 = 𝑡 ′ if and only if ⟨𝑡⟩𝜍𝑥 = ⟨𝑡 ′ ⟩𝜍𝑥 .
    (2) 𝑥 ⊨𝜍 ⊤ and 𝑥 ⊭𝜍 ⊥ (by Definition 2.12(2) ⊤ is sugar for 0 = 0                             Lemma 3.2. Suppose 𝜙 ∈ Pred, 𝑅 ∈ RCheck, and 𝜍 is an interpre-
        and ⊥ is sugar for 0 = 1).                                                             tation. Write ℓ = len(𝜍 (C)). Then:
    (3) 𝑥 ⊨𝜍 𝜙 ∧ 𝜙 ′ if and only if 𝑥 ⊨𝜍 𝜙 ∧ 𝑥 ⊨𝜍 𝜙 ′ .                                           (1) C ⊨𝜍 𝜙 when ⟨𝜙⟩𝜍𝑥 = 0 (equivalently using Definition 2.18:
    (4) 𝑥 ⊨𝜍 𝜙 ∨ 𝜙 ′ if and only if 𝑥 ⊨𝜍 𝜙 ∨ 𝑥 ⊨𝜍 𝜙 ′ .                                                𝑥 ⊨𝜍 𝜙) for every 𝑥 ∈ [ℓ].
    (5) ⊨𝜍 ∅.                                                                                          Note this gives C ⊨𝜍 𝜙 the flavour of a universal quantifica-
    (6) ⊨𝜍 𝑅, 𝑡 < C𝑖 if and only if ⊨𝜍 𝑅 ∧ ∀𝑥 ∈[ℓ].⟨𝑡⟩𝜍𝑥 < 𝜍 (C) @𝑖,𝑥 .                                tion of 𝜙 for 𝑋 ranging over 𝑥 ∈ [ℓ].
    (7) ⊨𝜍 𝑅, C𝑖 < 𝑡 if and only if ⊨𝜍 𝑅 ∧ ∀𝑥 ∈ [ℓ].𝜍 (C) @𝑖,𝑥 < ⟨𝑡⟩𝜍𝑥 .                          (2) C ⊨𝜍 𝑅 when ⟨𝑅⟩𝜍 = 0 (equivalently: ⊨𝜍 𝑅).
                                                                                                       We unpack what this means using Theorem 2.19(6&7): for every
  Proof. We reason as follows ([15, Theorem 2.4.4] has an analo-                                       𝑥 ∈ [ℓ], we have ⟨𝑡⟩𝜍𝑥 < 𝜍 (C) @𝑖,𝑥 for every 𝑡 < C𝑖 appearing
gous proof):                                                                                           in 𝑅, and ⟨𝑡⟩𝜍𝑥 > 𝜍 (C) @𝑖,𝑥 for every C𝑖 < 𝑡 appearing in 𝑅.
    (1) It is a fact that 0 = 0 and 1 ≠ 0.
    (2) It is a fact that 𝑥 = 𝑥 ′ if and only if (𝑥−𝑥 ′ ) 2 = 0.                                   Proof. Direct from Definition 3.1.                                      □
    (3) By non-negativity (Lemma 2.17).                                                           Remark 3.3. As per Lemma 3.2, C ⊨𝜍 𝜙; 𝑅 being valid has the
    (4) The product of two non-negative numbers is non-zero if and                             flavour of a universal quantification that 𝜙 and 𝑅 are valid for every
        only if they both are.                                                                 𝑥 ∈ [ℓ]. This gives our syntax from Figure 1 some extra expressivity,
    (5) It is a fact that 0 = 0.                                                               in that the index variable 𝑋 is universally quantified over [ℓ].
    (6) By construction: range checks compile to 0 and 1 (depending
        on values of the indicator function 𝜹). Their sum is zero if                              Remark 3.4. We continue Remark 2.15: predicates 𝜙 ∈ Pred
        and only if all summands are zero.                                                     (Figure 1) can express equality, conjunction, and disjunction on
    (7) As for the previous item.                                 □                            terms that include C𝑖 (𝑋 ) and C𝑖 C 𝑗 (𝑋 ). Range checks 𝑅 ∈ RCheck
                                                                                               can express range checks on the C𝑖 .
3    Arithmetising FOL                                                                            The integer semantics from Figure 3 maps this syntax to integers,
                                                                                               and Theorem 2.19 shows that this fits together in the sense that with
We now show how to arithmetise the FOL syntax from Figure 1, i.e.
                                                                                               these definitions, validity of predicates and range checks behaves
to map FOL to polynomials that match up, in a sense made formal
                                                                                               in the way that the symbols would lead us to expect. For example:
by Theorem 3.8, with the integer semantics of Theorem 2.19.
                                                                                               𝑥 ⊨𝜍 𝜙 ∧ 𝜙 ′ is indeed valid if and only if 𝑥 ⊨𝜍 𝜙 is valid and 𝑥 ⊨𝜍 𝜙 ′
    Definition 3.1.   (1) Say 𝜙 ∈ Pred uses C 𝑗 as a pointer when                              is valid; and 𝑡 < C𝑖 is indeed valid when ⟨𝑡⟩𝜍𝑥 is a lower bound for
        𝜙 contains a subterm of the form C𝑖 C 𝑗 (𝑋 ).                                          the 𝑖th row of 𝜍 (C).
zk-SNARKs for First Order Logic                                                                                      Conference acronym ’XX, June 03–05, 2018, Woodstock, NY


   As per Remark 2.15, we will now connect our integer semantics                                 Proof. By a routine induction on syntax. The interesting cases
to a multivariate polynomial semantics which we build using the                               are for 𝑋 , C𝑖 (𝑋 ), and C𝑖 C 𝑗 (𝑋 ):
enriched polynomials from Figure 2.
                                                                                               𝛽 F (mkQ𝑥F ⟨𝑋 ⟩)
   We now define mkQ (read ‘make 𝑄’) taking enriched polynomials                                        = 𝛽 F (mkQ𝑥F 𝑋 )                             Figure 2
to multivariate polynomials. Intuitively, mkQ𝑥F is what computes                                        = 𝛽 F (𝑥)                                    Figure 4
the polynomials 𝑄 ∈ Q used in equation (1). We pad binary expan-                                        =𝑥                                           Def. 3.6(2)
sions of the elements of the images of the f𝑖 ∈ F so that all binary                                    = ⟨𝑋 ⟩𝜍𝑥                                     Figure 3
expansions have the same length, equal to the largest bit-length ob-
taining over all the ranges of the f𝑖 . Write maxbl for the maximum                            𝛽 F (mkQ𝑥F ⟨C𝑖 (𝑋 )⟩)
                                                                                                                         0,𝑥            0,𝑥
bit-length of the elements in the images of the f𝑖 .                                                    = 𝛽 F (b2int (𝐵𝑖,1   , . . . , 𝐵𝑖,maxbl ))   Figures 2 & 4
                                                                                                        = b2int ( ∅b f𝑖 (𝑥))                         Def. 3.6
   Definition 3.5. Suppose maxbl, ℓ > 0, 𝑥 ∈ [ℓ], and F = (f𝑖 :                                         = f𝑖 (𝑥)                                     Lemma 2.3
[ℓ] → N | 𝑖 ∈ [ar (C)]). Define mkQ𝑥F mapping enriched polyno-                                          = 𝜍 (C) @𝑖,𝑥                                 Def. of F , 𝑥 ∈ [ℓ]
mials (Definition 2.12(1)) to multivariate polynomials                                                  = ⟨C𝑖 (𝑥)⟩𝜍𝑥                                 Figure 3
                                                         ar (C),ℓ         ar (C),ℓ
 mkQ𝑥F : EP → Z[𝐵 1,1
                  0,1             0,1
                      , . . . , 𝐵 1,maxbl , . . . , 𝐵 ar (C),1, . . . , 𝐵 ar (C),maxbl ]       𝛽 F (mkQ𝑥F ⟨C𝑖 C 𝑗 (𝑋 )⟩)
                                                                                                                          𝑗,𝑥         𝑗,𝑥
                                                                                                        = 𝛽 F (b2int (𝐵𝑖,1 , . . . , 𝐵𝑖,maxbl ))     Figures 2 & 4
as per Figure 4.
                                                                                                        = f𝑖 (f 𝑗 (𝑥))                               Def. 3.6 & Lemma 2.3
    Next we define an evaluation map 𝛽 F as a composition of the                                        = 𝜍 (C) @𝑖,𝜍 (C) @𝑗,𝑥                        Def. of F , 𝑓 𝑗 (𝑥) ∈ [ℓ]
𝜋 𝜈 , ∅b , and the f𝑖 :                                                                                 = ⟨C𝑖 C 𝑗 (𝑋 )⟩𝜍𝑥                            Figure 3

   Definition 3.6. Suppose maxbl, ℓ > 0 and F = (f𝑖 : [ℓ] → N |                                                                                                             □
𝑖 ∈ [ar (C)]).7 Then:                                                                            Corollary 3.9. Suppose 𝜍 is an interpretation such that 𝜍 (C) ∈
    (1) For each 𝑖 ∈ [ar (C)] and 𝑗 ∈ {0} ∪ [ar (C)] and 𝑥 ∈ [ℓ] and                          Mar (C) ×ℓ (N). Suppose C ⊨ 𝜙; 𝑅 is a judgement (so that 𝜙 ∈ Pred and
                                      0,𝑥
        𝜈 ∈ [maxbl], we define 𝛽 F (𝐵𝑖,𝜈
                                                      𝑗,𝑥
                                          ) and 𝛽 F (𝐵𝑖,𝜈 ) by                                𝑅 ∈ RCheck and (𝜙, 𝑅) is properly range-checked). Define F = (f𝑖 =
                                                                                              (𝑥 ∈[ℓ] ↦→ 𝜍 (C) @𝑖,𝑥 ) | 𝑖 ∈ [ar (C)]). Then:
                     0,𝑥
               𝛽 F (𝐵𝑖,𝜈 ) = π𝜈 ∅b f𝑖 (𝑥) and                                                 C ⊨𝜍 𝜙; 𝑅    if and only if
                             (
                     𝑗,𝑥       π𝜈 ∅b f𝑖 (f 𝑗 (𝑥)) if f 𝑗 (𝑥) ∈ [ℓ]                                   ∀𝑥 ∈ [ℓ]. 𝛽 F (mkQ𝑥F ⟨𝜙⟩) = 0 ∧
               𝛽 F (𝐵𝑖,𝜈 ) =
                               0                  if f 𝑗 (𝑥) ∉ [ℓ]                                   ∀𝑥 ∈ [ℓ]. 𝛽 F (mkQ𝑥F ⟨𝑡⟩) < 𝜍 (C) @𝑖,𝑥 for every 𝑡 < C𝑖 in 𝑅 ∧
                                  0,𝑥
                                                                                                     ∀𝑥 ∈ [ℓ]. 𝛽 F (mkQ𝑥F ⟨𝑡⟩) > 𝜍 ( C) @𝑖,𝑥 for every C𝑖 < 𝑡 in 𝑅
         Thus in words: 𝛽 F maps 𝐵𝑖,𝜈 to the 𝜈th bit of the binary
        expansion of f𝑖 (𝑥); and 𝛽 F maps 𝐵𝑖,𝜈 to the 𝜈th bit of the                             Proof. Routine from Theorem 3.8 and Lemma 3.2. The theorem
                                                          𝑗,𝑥
                                                                                              requires F to be in-range (Definition 3.7); this follows from our
        binary expansion of f𝑖 (f 𝑗 (𝑥)) (if this is in-range).
                                                                                              assumption that (𝜙, 𝑅) is range-checked (Definition 3.1(2)).   □
    (2) We extend 𝛽 F to an evaluation map on multivariate poly-
        nomials, in the natural way by instantiating variable sym-
                                                                                              4    A zk-SNARK for Relations in First Order Logic
                                       0,2
        bols. For example: 𝛽 F (0 + 𝐵 1,3       0,5
                                            ∗ 𝐵 4,6 ) = 0 + (π3 ∅b f1 (2)) ∗
                                                                                              Below, we describe in Lemma 4.2 how to transform instances of
        (π6 ∅b f4 (5)). 8
                                                                                              relations defined in first order logic to instances of relations de-
   Definition 3.7. Suppose F = (f𝑖 : [ℓ] → N | 𝑖 ∈ [ar (C)]) and                              fined using multivariate polynomials, using Corollary 3.9. These
𝑡 ∈ Term and 𝜙 ∈ Pred. Call F in-range for 𝑡 / for 𝜙 when for                                 latter relations are suitable inputs to Zinc-PIOP. We do not require
every 𝑗 that 𝑡 / 𝜙 uses as a pointer, we have ∀𝑥 ∈ [ℓ].1 ≤ f 𝑗 (𝑥) ≤ ℓ.                       auxiliary data in the index i, so we only consider instance-witness
                                                                                              pairs ( x, w) below. We first define relations for predicates in Pred
   A central technical result is that 𝛽 F ◦ mkQ𝑥F ◦ ⟨·⟩ equals ⟨·⟩𝜍𝑥 :                        and range checks in RCheck:
   Theorem 3.8. Suppose 𝑡 ∈ Term and 𝜙 ∈ Pred and 𝜍 is an                                        Definition 4.1. Suppose 𝜙 ∈ Pred (the predicate language from
interpretation. Write ℓ = len(𝜍 (C)) and suppose 𝑥 ∈ [ℓ]. Define                              Figure 1), and 𝑅 ∈ RCheck, and 𝜍 is an interpretation. Let ℓ =
F = (f𝑖 = (𝑥 ∈[ℓ] ↦→ 𝜍 (C) @𝑖,𝑥 ) | 𝑖 ∈ [ar (C)]). If F is in-range for 𝑡                     𝑙𝑒𝑛(𝜍 (C)). Define two relations:
and 𝜙 (Definition 3.7), then:                                                                                
                                                                                                                                 𝜍 (C) ∈ Mar (C) ×ℓ (N)
                                                                                                                                                           
                                                                                                  RELFOL
                                                                                                      gp =      ((𝜙, 𝑅), 𝜍)                                   and
         𝛽 F (mkQ𝑥F ⟨𝑡⟩) = ⟨𝑡⟩𝜍𝑥          and     𝛽 F (mkQ𝑥F ⟨𝜙⟩) = ⟨𝜙⟩𝜍𝑥                                                        C ⊨𝜍 𝜙; 𝑅
                                                                                                                                                              
                                                                                                                                      𝜍 (C) ∈ Mar (C) ×ℓ (N)
                                                                                                   RELEPgp =     (⟨𝜙⟩, 𝑅), 𝜍 (C)
7 In the case of a cryptographic application to arithmetise FOL relations to AIRs, a                                                   C ⊨𝜍 𝜙; 𝑅
verifier V will not have direct access to the f𝑖 , instead having oracle access to them via
a polynomial commitment scheme.                                                                  The relation RELEP
                                                                                                                 gp is an intermediate relation obtained by turn-
8 Unpicking the symbol salad, this is zero plus the AND of the third bit of the binary
expansion of f1 (2) with the sixth bit of the binary expansion of f4 (5) . (Why? It’s an      ing instances of RELFOL
                                                                                                                   gp into enriched polynomials, via Figure 2.
example.)                                                                                     By converting 𝜙 to ⟨𝜙⟩, we obtain an enriched polynomial instance
Conference acronym ’XX, June 03–05, 2018, Woodstock, NY                                                                                           Murdoch J. Gabbay and Andrew Mendelsohn


            mkQ𝑥F (𝑞) = 𝑞          mkQ𝑥F (𝑃 + 𝑃 ′ ) = mkQ𝑥F (𝑃) + mkQ𝑥F (𝑃 ′ )                        mkQ𝑥F (𝑃 ∗ 𝑃 ′ ) = mkQ𝑥F (𝑃) ∗ mkQ𝑥F (𝑃 ′ ) mkQ𝑥F (len(C)) = ℓ
            mkQ𝑥F (𝑋 ) = 𝑥         mkQ𝑥F (C𝑖 (𝑋 )) = b2int (𝐵𝑖,1                                     mkQ𝑥F (C𝑖 C 𝑗 (𝑋 )) = b2int (𝐵𝑖,1 , . . . , 𝐵𝑖,maxbl )
                                                             0,𝑥            0,𝑥                                                    𝑗,𝑥            𝑗,𝑥
                                                                 , . . . , 𝐵𝑖,maxbl )
Above, 𝑖 ∈ [ar (C)], 𝑗 ∈ {0} ∪ [ar (C)], and maxbl, ℓ ∈ N ≥1 and 𝑥 ∈ [ℓ] and F = (f𝑖 : [ℓ] → N | 𝑖 ∈ [ar (C)]) is an ar (C)-tuple of functions.
Note that 𝑗 ∈ {0} ∪ [ar (C)] yet C0 (𝑋 ) is not defined - this will not trouble us because a FOL validity predicate will never transform to an
                 enriched polynomial supported on C0 (𝑋 ). Thus the clauses for C𝑖 (𝑋 ) and C𝑖 C 𝑗 (𝑋 ) have disjoint images.

                             Figure 4: From enriched polynomials EP to multivariate polynomials MVP (Definition 3.5)


preserving the logical content of 𝜙, with a witness w = 𝜍 being                                           corresponding to this data. Set the instance-witness pair in RELgp′ ,Q ′
knowledge of 𝜍 (C) ∈ Mar (C) ×ℓ (N) satisfying 𝜙.                                                         to be
   We now use mkQ𝑥F (Figure 4) to map enriched polynomials                                                      ( x, w) = ([[ 𝑓˜1 ]], . . . , [[ 𝑓˜
                                                                                                                                                   ar (C)
                                                                                                                                                          ]]), ( 𝑓˜1 , . . . , 𝑓˜
                                                                                                                                                                                 ar (C) 
                                                                                                                                                                                       )
                                                                                                                                    𝜍 (C)            𝜍 (C)         𝜍 (C)        𝜍 (C)
to multivariate polynomials, setting F = ( 𝑓˜𝑖    | 𝑖 ∈ [ar (C)]),    𝜍 (C)
i.e. F comprises the multilinear extensions of the rows of 𝜍 (C).                                         where [[·]] denotes an oracle to the argument,10 and
Note that, before padding, the 𝑓˜𝜍𝑖 (C) are multilinear polynomials in                                                            Q ′ = (mkQ𝑥F ⟨𝜙⟩)𝑥 ∈ [len(𝜍 (C) ) ]
𝜇 = ⌈log2 ℓ⌉ variables. However, for pointer correctness, we pad so                                       We claim this data represents an AIR for some gp′ : note that for each
that 𝜇 = max( ⌈log2 ℓ⌉, maxbl).9                                                                          𝑥 ∈ [len(𝜍 (C))], mkQ𝑥F ⟨𝜙⟩ is a multivariate polynomial determined
    By Corollary 3.9, with F = ( 𝑓˜𝜍𝑖 (C) | 𝑖 ∈ [ar (C)]) and defin-                                      by 𝜙, evaluating to zero on a subset of the binary decompositions
            𝑗                        𝑗
ing 𝑓˜𝑖 ( 𝑓˜ (𝑥)) := 𝑓˜𝑖 ( ∅b 𝑓˜ (𝑥)), we have that RELEP of                                                            ∅b 𝑓˜𝜍1(C) ( ∅b 1), . . . , ∅b 𝑓˜𝜍ar(C)(C) ( ∅b len(𝜍 (C)))
                                                                                                                                                                                    
       𝜍 (C)      𝜍 (C)             𝜍 (C)        𝜍 (C)                                          gp
Definition 4.1 is equivalent to
                                                                                                         To ensure that the oracle queries return binary values to the verifier
                
                
                 ((mkQ𝑥F ⟨𝜙⟩)𝑥 ∈ [ℓ ] , 𝑅), ( 𝑓˜𝜍𝑖 (C) )𝑖 ∈ [ar (C) ] 
                                                                                                         we append the polynomials 𝑥 1 (𝑥 1 − 1), . . . , 𝑥 𝜇 (𝑥 𝜇 − 1) to Q ′ ; for
                
                                                                       
                                                                        
      RELMV
         gp,F =       𝜍 (C) ∈ Mar (C) ×ℓ (N), C ⊨𝜍 𝑅,                                                     each response from the oracle the verifier will check the vector
                                                                                                          has length 𝜇 and use the 𝑥𝑖 (𝑥𝑖 − 1) to ensure that the oracle has
                                                                       
                
                     ∀𝑥 ∈[ℓ] (𝛽 F (mkQ𝑥F ⟨𝜙⟩) = 0)                     
                                                                        
                                                                                                          returned data of the correct data type, namely bits.11
                                                                       
   By choosing F = { 𝑓˜𝑖    | 𝑖 ∈ [ar (C)]}, we find that the condi-                                          Next, since a range check may be encoded as an algebraic indexed
                                  𝜍 (C)
tion that the image of 𝛽 F on the multivariate polynomial mkQ𝑥F ⟨𝜙⟩                                       relation (equation (2)), for all range check conditions in 𝑅 we may
satisfies 𝛽 F (mkQ𝑥F ⟨𝜙⟩) = 0 is equivalent to mkQ𝑥F ⟨𝜙⟩ evaluating                                       form a corresponding AIR with a set of defining polynomials Q𝑅
to zero at some subset of                                                                                 and global parameters gp′′ . We then combine the two AIRs we have
                                                                                                          constructed, setting Q := Q ′ ∪ Q𝑅 , appending the instance-witness
           ( ∅b (𝜍 (C) @1,1 ), . . . , ∅b (𝜍 (C) @ar (C),ℓ ))                                             data of the range check relation to the former relation RELgp′ ,Q ′ ,
                                                                              ar ( C )
                                     = ( ∅b 𝑓˜𝜍1( C ) ( ∅b 1) , . . . , ∅b 𝑓˜𝜍 ( C ) ( ∅b ℓ))             and denoting the updated global parameters by gp1 .
                                                                                                              The claim that ( x, w) is well-formed if and only if C ⊨𝜍 𝜙; 𝑅 is di-
(recall from Notation 2.1(6) that 𝜍 (C) @𝑖,𝑗 is the 𝑖, 𝑗th entry of 𝜍 (C))                                rect from Corollary 3.9: well-formed ( x, w) have integer entries and
as long as the range checks in 𝑅 guarantee that any pointer C𝑖 (𝑋 )                                       satisfy the polynomial relations in Q, whose constraints guarantee
in 𝜙 corresponds to a row 𝜍 (C)𝑖 with entries bounded by len(𝜍 (C)).                                      that C ⊨𝜍 𝜙 and C ⊨𝜍 𝑅. The converse holds by construction.              □
   We now prove that RELMV gp,F
                                provides algebraic indexed relations:                                                                  
                                                                                                              For instances (𝜙, 𝑅), 𝜍 to generate valid inputs to Zinc, they
   Lemma 4.2. Let gp0, gp1 denote global parameters, and fix 𝜕, 𝜇 > 0.                                    must also be well-formed:
Let 𝜙 be a predicate defined over Z in a matrix variable symbol C. Let
                                                                                                              Definition 4.3. An instance (𝜙, 𝑅), 𝜍 ∈ RELFOL
                                                                                                                                                   
𝜍 (C) ∈ Mar (C) ×ℓ (N) be an interpretation, and 𝑅 be a set of range                                                                                         gp is well-formed
                                                                                                          if it transforms via the transform described in Lemma 4.2 to an
check conditions on 𝜍 (C). Set F = { 𝑓˜𝜍𝑖 (C) ∈ Z!!𝜕 [X] | 𝑖 ∈ [ar (C)]}.
                                                                                                          instance of RELgp,Q , for some F and Q, which is well-formed as
Then the data of an instance of RELEP  gp0 can be expressed as a pair                                     an algebraic indexed relation.
( x, w) of RELgp1 ,Q for some gp1 and some Q, such that ( x, w) is
well-formed if and only if C ⊨𝜍 𝜙; 𝑅 is valid.                                                               Lemma 4.2 shows that we may efficiently compile well-formed
                                                                                                          instance-witness pairs defined in the syntax of FOL (matrix variable
   Proof. Let                                                                                             symbols and enriched polynomials), into algebraic indexed relation
                                                                                                         instance-witness pairs which are valid inputs to Zinc-PIOP. Once
       ((mkQ𝑥F ⟨𝜙⟩)𝑥 ∈ [len(𝜍 (C) ) ] , 𝑅), ( 𝑓˜𝜍𝑖 (C) )𝑖 ∈ [ar (C) ] ∈ RELMV
                                                                           gp,F                           we have instance-witness pairs of a form which may be provided
be obtained from some instance ((𝜙, 𝑅), 𝜍) ∈ RELEP     gp0 . We begin by                                  10Which oracle will later be instantiated with a PCS such as Zip [18, Section 5].
considering (mkQ𝑥F ⟨𝜙⟩)𝑥 ∈ [len(𝜍 (C) ) ] : we define an AIR, RELgp′ ,Q ′ ,                               11 Pedant note: we implicitly appeal to a syntactic category of formal symbols from
                                                                                                          which to draw the 𝑥𝑖 . We emphasise this because elsewhere in this paper, 𝑥 is used as
9 More explicitly, the 𝑓˜𝑖    have domain [len(𝜍 (C) ) ] , so inputs are of bit length at                 a meta-level variable ranging over values. So for clarity: the 𝑥 s-with-subscript written
                        𝜍 (C)                                                                             here are formal polynomial variable symbols; 𝑥 -without-any-subscript looks similar
most ⌈log2 (len(𝜍 (C) ) ) ⌉ = 𝜇 , and have range comprising elements of bit length at                     but is actually a variable ranging over values. Note that including the 𝑥𝑖 (𝑥𝑖 − 1) in
most maxbl . To form the composition 𝑓˜𝜍𝑖 (C) ( ∅b 𝑓˜𝜍 (C) ) , we require that the length of
                                                      𝑗
                                                                                                          Q ′ for all 𝑖 ∈ [ar (C) ] is equivalent to including the polynomials 𝐵𝑖,𝜈 (𝐵𝑖,𝜈 − 1) in
                                                                                                                                                                                      𝑗,𝑥  𝑗,𝑥

                                                                                                          Q ′ for all 𝑖 ∈ [ar (C) ] , 𝑗 ∈ {0} ∪ [ar (C) ] , 𝑥 ∈ [len(𝜍 (C) ) ] , and 𝜈 ∈ [𝜇 ] .
      𝑗
∅b 𝑓˜
   𝜍 (C)
        is identical to the bit length of inputs to 𝑓˜𝑖 . 𝜍 (C)
zk-SNARKs for First Order Logic                                                                                         Conference acronym ’XX, June 03–05, 2018, Woodstock, NY


as the input to a PIOP (such as Zinc-PIOP), we can commit to                                      Next, consider the instances of RELgp′′ ,QLook (cf. equation (2))
the witness data using a PCS and compile the PIOP to obtain a                                  corresponding to 𝑅; any single range check 𝑅𝑖 ∈ 𝑅 has global
zk-SNARK.                                                                                      parameters
     Observe from Figure 4 that mkQ𝑥F ⟨𝜙⟩ may contain subterms                                                     gp𝑖′′ = (1, 0, 1, log 𝑛𝑎 + log 𝑛𝑡 , 𝜕)
corresponding to C𝑖 C 𝑗 (𝑋 ), whose indices depend on evaluations                              for some 𝑛𝑎 , 𝑛𝑡 . We next compute log 𝑛𝑎 and log 𝑛𝑡 .
f 𝑗 (𝑥) = 𝑓˜𝜍 ( C ) ( ∅b 𝑥). Recall further that such 𝑓˜𝜍 (C) are ‘pointers’
             𝑗                                           𝑗
                                                                                                  Recall log 𝑛𝑎 is the number of variables on which the multilinear
obtained from interpolating a subset of the rows of 𝜍 (C). Since these                         extension comprising the range check witness w = 𝑎(X) is defined.
values (equivalently, interpolating polynomials) are not public, but                           Since the range checks in 𝑅 define range checks on the rows of 𝜍 (C),
rather are part of the witness inside a polynomial commitment,                                 we may take 𝑎(X) = 𝑓˜𝜍𝑖 (C) for some 𝑖 ∈ [ar (C)] and so each range
when running a PIOP on the relations constructed in Lemma 4.2 we                               check in 𝑅 comprises at most len(𝜍 (C)) integer range checks. We
stipulate that a verifier who verifies that 𝛽 F (mkQ𝑥F ⟨𝜙⟩) = 0 must                           then have that 𝑛𝑎 may be taken to be the minimal integer satisfying
                                                   𝑗
first query the polynomial commitments [[ 𝑓˜ (𝑋 1, . . . , 𝑋 𝜇 )]] in w                        ⌈log 𝑛𝑎 ⌉ = maxbl = 𝜇. By padding appropriately we may take
                                                           𝜍 (C)
          𝑗                                                                                    log 𝑛𝑎 = 𝜇.
for ∅b 𝑓˜𝜍 ( C ) ( ∅b 𝑥) for all 𝑗 for which 𝜍 (C) 𝑗 acts as a pointer, which                     Recall 𝑡 (Y) is the multilinear extension interpolating the set in
values then define mkQ𝑥F ⟨𝜙⟩. We assume that the PCS returns                                   which the evaluations of 𝑎(X) should lie. Since range checks in our
the bits of the queried entry of the witness data. Aside from this                             semantics arise to ensure pointers are well-defined, range checks
additional step, our zk-SNARK uses a multilinear PCS to provide                                ensure that the entries of some rows of 𝜍 (C) lie in [len(𝜍 (C))]. Thus
input relations to a PIOP which is run in an otherwise standard                                we have log 𝑛𝑡 = 𝜇 also.
manner.                                                                                           Finally, since 𝑅 may contain many range checks, we find that
  Corollary 4.4. Let 𝜆 denote a security parameter. Suppose 𝜙 ∈                                the parameters to perform all the range checks in 𝑅 are
Pred and 𝑅 ∈ RCheck and 𝜍 is an interpretation satisfying 𝜍 (C) ∈                                                      gp′′ = (|𝑅|, 0, 1, (|𝑅| + 1)𝜇, 𝜕)
Mar (C) ×len(𝜍 (C) ) (N), with ar (C), len(𝜍 (C)) ∈ Z ≥1 satisfying ar (C) =
                                                                                               To compute the final parameters gp = (𝑘, 𝑚, 𝑛, 𝜇, 𝜕) of our AIR
poly(𝜆), len(𝜍 (C)) = poly(𝜆). Set 𝜇 := maxbl. Set F = { 𝑓˜𝜍𝑖 (C) ∈                            instance, we note that since the range checks are performed on the
Z!!𝜕 [X] | 𝑖 ∈ [ar (C)]} for some 𝜕 > 0. Then there exists a zk-                               same witness data as in the RELgp′ ,Q ′ instance, we have 𝑘 = ar (C).
SNARK to convince a verifier that a well-formed instance ((𝜙, 𝑅), 𝜍) ∈                         Moreover, the same choice of 𝑡 (Y) can be used for each range check,
RELFOLgp satisfies C ⊨𝜍 𝜙; 𝑅, with soundness error 𝜀𝑠𝑜𝑢𝑛𝑑 equal to                             so 𝑛 = 1. Thus the final parameters of the AIR instance are
the soundness error of Zinc, instantiated with global parameters                                                      gp = (ar (C), 0, 1, (|𝑅| + 2)𝜇, 𝜕)
gp = (ar (C), 0, 1, (|𝑅| + 2)𝜇, 𝜕).
                                                                                                                                                                                   □
   Proof. As in Lemma 4.2 we transform the instance ((𝜙, 𝑅), 𝜍) ∈
                                                                                                  Remark 4.5. The verifier complexity of our zk-SNARK is inher-
RELEPgp into an equivalent instance ( x, w) ∈ RELgp,Q which is a
valid input to Zinc-PIOP, for some parameters gp = (𝑘, 𝑚, 𝑛, 𝜇, 𝜕).                            ited from the verifier complexity of the zk-SNARK used under the
The claim concerning the soundness error then follows from run-                                hood of Zinc. The verifier sees a proof, which they verify.
ning a zk-SNARK compiled from Zinc-PIOP and Zip. To conclude                                      The prover complexity is more complicated. If the input in-
the corollary, it suffices to compute the global parameters. For the                           stance is defined on the len(𝜍 (C)) polynomials {mkQ𝑥F ⟨𝜙⟩}, then
reader’s benefit, we recall the meaning of each such parameter: 𝑘 is                           the prover complexity is directly inherited from the prover com-
the number of multilinear polynomials 𝑓𝑖 comprising the witness;                               plexity of Zinc’s zk-SNARK.
𝑚 is the rank of the auxiliary data y in the instance; 𝑛 is the number                            However, if the input instance is defined from an arbitrary FOL
of indexing multilinear polynomials 𝑔𝑖 in i; 𝜇 is the dimension of                             predicate, then the prover has to perform the transformations of
the hypercube onto which the 𝑓𝑖 and 𝑔𝑖 interpolate; and 𝜕 is the                               Figures 2 and 4 to obtain the mkQ𝑥F ⟨𝜙⟩. At a high level (this is not a
bit-length bound on the coefficients of the instance-witness data.                             mathematical proof) to compute the enriched polynomial ⟨𝜙⟩ from
                                                                     
   Let ((mkQ𝑥F ⟨𝜙⟩)𝑥 ∈ [len(𝜍 (C) ) ] , 𝑅), ( 𝑓˜𝜍𝑖 (C) )𝑖 ∈ [ar (C) ] ∈ RELMV                  𝜙 using Figure 2 requires (assuming no optimisations) to compute
                                                                               gp,F            a product of sums of squares schema of this form:
be obtained from the instance ((𝜙, 𝑅), 𝜍). Following the proof of                                                        ÎÍ
Lemma 4.2, we then convert these data into an AIR for Zinc. We ob-                                                 ⟨𝜙⟩ =      (C𝑟 (𝑋 ) − C𝑠 (𝑋 )) 2
tain one instance-witness pair by considering (mkQ𝑥F ⟨𝜙⟩)𝑥 ∈ [len(𝜍 (C) ) ]                    To compute the polynomials mkQ𝑥F ⟨𝜙⟩ we replace the C𝑟 (𝑋 ) with
and another by considering the range checks 𝑅; by relabelling in-
                                                                                               the b2int (𝐵𝑟,1 , . . . , 𝐵𝑟,maxbl ) (and likewise the C𝑟 C𝑠 (𝑋 )) for
                                                                                                              𝑗,𝑥        𝑗,𝑥
dices and defining Q, i, x, and w appropriately we can combine
                                                                                                          b2int (𝐵𝑟,1 , . . . , 𝐵𝑟,maxbl ) − b2int (𝐵𝑠,1 , . . . , 𝐵𝑠,maxbl )
these two instances into a single Zinc input relation tuple. Here,                                ÎÍ                 𝑗,𝑥         𝑗,𝑥                 𝑗,𝑥            𝑗,𝑥       2
however, we (equivalently) consider the two relations side by side,
for clarity.                                                                                   This can be left in an unexpanded form until one computes the
   First consider RELgp′ ,Q ′ where                                                            𝛽 F (mkQ𝑥F ⟨𝜙⟩), at which point the whole polynomial is evaluated
                                                                                               at the relevant bit strings.
    Q ′ := (mkQ𝑥F ⟨𝜙⟩)𝑥 ∈ [len(𝜍 (C) ) ] , 𝑥 1 (𝑥 1 − 1), . . . , 𝑥 𝜇 (𝑥 𝜇 − 1) ,
                                                                               
                                                                                                  To the above we should note that this is generic case for an
                                       ar (C)                                   ar (C)         arbitrary predicate 𝜙. However, in practice provers do not gener-
and x = ( [[ 𝑓˜𝜍1(C) ]], . . . , [[ 𝑓˜𝜍 (C) ]]), and w = ( 𝑓˜𝜍1(C) , . . . , 𝑓˜𝜍 (C) ). Here
                                                                                               ate arbitrary 𝜙; they generate 𝜙 with specific structure reflecting
                              gp′ = (ar (C), 0, 0, 𝜇, 𝜕)                                       specific meaning. Thus there may be a design space of optimal
Conference acronym ’XX, June 03–05, 2018, Woodstock, NY                                                                Murdoch J. Gabbay and Andrew Mendelsohn


syntactic forms for predicates, which optimise proving. This is a fa-            See [15, Lemma 3.2.6] for a proof that (𝜙 pow, 𝑅pow ) does indeed
miliar pattern: design spaces of optimal syntactic forms are known            encode Definition 5.1. We therefore consider instances of the rela-
for other computational applications of logic (e.g. the Horn clause           tion
theories of logic-programming). It would not be a surprise to find                          
                                                                                                           𝜙 = 𝜙 pow, 𝑅 = 𝑅pow, C = pow     
                                                                                  RelFOL
similar structure in this new computational application of logical                          
                                                                                                                                             
                                                                                                                                              
                                                                                     gp =  ((𝜙, 𝑅), 𝜍)     𝜍 (C) ∈ M4×len(𝜍 (C) ) (N)
syntax; investigating this is future work.                                                                  C ⊨𝜍 𝜙; 𝑅
                                                                                                                                              
                                                                                                                                              
                                                                                                                                             
   Remark 4.6. We note that the set Q ′ contains len(𝜍 (C)) polyno-              Applying the transform of Figure 2 to 𝜙 pow , we obtain an en-
mials mkQ𝑥F ⟨𝜙⟩. Moreover, the equivalence between the initial FOL            riched polynomial instance in
instance and the instance we construct as an input to Zinc-PIOP
holds only if 𝛽 F (mkQ𝑥F ⟨𝜙⟩) = 0 for all 𝑥 ∈ [len(𝜍 (C))]. To avoid
                                                                                             
                                                                                                             𝜙 = 𝜙 pow, 𝑅 = 𝑅pow, C = pow                                 
                                                                                                                                                                           
                                                                                  RelEP
                                                                                             
                                                                                                                                                                          
                                                                                                                                                                           
checking that each and every mkQ𝑥F ⟨𝜙⟩ evaluates to zero under                       gp =      ((⟨𝜙⟩, 𝑅), 𝜍)  𝜍 (C) ∈ M4×len(𝜍 (C) ) (N)
                                                                                                                                                                          
𝛽 F , we can run a ‘random linear combinations’ step in which the
                                                                                             
                                                                                                             C ⊨𝜍 𝜙; 𝑅                                                    
                                                                                                                                                                           
verifier sends ℓ𝜍 (C) = len(𝜍 (C)) uniformly random challenges 𝑐𝑖                                                                 
                                                                                 where ⟨𝜙 pow ⟩ = pow2 (𝑋 ) 2 + (pow3 (𝑋 ) − 1) 2 ∗
from a suitable challenge set and the prover proves that the random                                                               2
linear combination                                                                                  pow1 (𝑋 ) − pow1 (pow4 (𝑋 ))
                                                                                                                                         2
       (C)
    ℓ𝜍∑︁                                         ℓ𝜍 (C)                                           + pow2 (𝑋 ) − (pow2 (pow4 (𝑋 )) + 1)
                                       © ∑︁                                                                                                                            2
             𝑐 𝑥 · mkQ𝑥F ⟨𝜙⟩                  𝑐 𝑥 · mkQ𝑥F ⟨𝜙⟩ ® = 0                                      + pow3 (𝑋 ) − pow1 (𝑋 ) ∗ pow3 (pow4 (𝑋 ))
                                                              ª
                                satisfies
                                    𝛽F ­
   𝑥=1                                   𝑥=1
                                                                                 We then apply mkQ𝑥F with F = {( 𝑓˜𝜍𝑖 (pow) )𝑖 ∈ [4] } to obtain an
                                       «                      ¬
This comes at the cost of a small increase in the soundness error of
                                                                              instance in
the protocol, and the details are beyond the scope of this paper.
   We leave as an open question the task of preprocessing the input                             
                                                                                                    ((mkQ𝑥F ⟨𝜙⟩)𝑥 ∈ [𝑙𝑒𝑛 (𝜍 (C) ) ] , 𝑅), ( 𝑓˜𝜍𝑖 (C) )𝑖 ∈ [4]
                                                                                                                                                                    
                                                                                                                                                                     
                                                                                                                                                                    
FOL relations into a logically equivalent form which arithmetises                               
                                                                                                                                                                    
                                                                                                                                                                     
                                                                                                
                                                                                                       𝜙 = 𝜙 pow, 𝑅 = 𝑅pow, C = pow                                 
                                                                                                                                                                     
to an AIR of lowest complexity.                                                  RELMV
                                                                                    gp,F =  
                                                                                                       𝜍 (C) ∈ M4×len(𝜍 (C) ) (N), C ⊨𝜍 𝑅,                          
                                                                                                                                                                     
                                                                                                                                                                    
                                                                                                       ∀𝑥 ∈[len(𝜍 (C))] (𝛽 F (mkQ𝑥F ⟨𝜙⟩) = 0)                       
5     Two examples of arithmetisation in action
                                                                                                                                                                    
                                                                                                                                                                    
   Arithmetising Power Functions. A common use of zk-SNARKs                      By Figure 4 the instance polynomials have the form
sees a prover convince a verifier that the prover has computed the
output of some function. We now show how a prover can prove                    mkQ𝑥F ⟨𝜙 pow ⟩
knowledge of values of a function expressed in FOL. We consider
                                                                                         = mkQ𝑥F (pow2 (𝑋 )) 2 + (mkQ𝑥F (pow3 (𝑋 )) − 1) 2 ∗
                                                                                                                                          
the power function:                                                                       
                                                                                            mkQ𝑥F (pow1 (𝑋 )) − mkQ𝑥F (pow1 (pow4 (𝑋 )))
                                                                                                                                          2
   Definition 5.1. The standard inductive definition of 𝑎𝑏 for 𝑎, 𝑏 ∈
N is a function pow(𝑥, 𝑦) satisfying:                                                       + mkQ𝑥F (pow2 (𝑋 )) − (mkQ𝑥F (pow2 (pow4 (𝑋 ))) + 1)
                                                                                                                                                                               2

              base case              pow(𝑎, 0) = 1                                          + mkQ𝑥F (pow3 (𝑋 ))
                                                                                                                                               
              inductive step         pow(𝑎, 𝑏 + 1) = 𝑎 ∗ pow(𝑎, 𝑏)
                                                                                              −mkQ𝑥F (pow1 (𝑋 )) ∗ mkQ𝑥F (pow3 (pow4 (𝑋 )))
                                                                                                                                            2

    This may be written in first order logic as
                                                                                         = b2int (𝐵 2,1
                                                                                                    0,𝑥             0,𝑥 2               0,𝑥              0,𝑥         
                                                                                                        , . . . , 𝐵 2,𝜇 ) + (b2int (𝐵 3,1    , . . . , 𝐵 3,𝜇 ) − 1) 2 ∗
     ∀𝑎.(pow(𝑎, 0) = 1) ∧ ∀𝑎, 𝑏.(pow(𝑎, 𝑏 + 1) = 𝑎 ∗ pow(𝑎, 𝑏)),                          
We define the corresponding predicate below, where 𝜙 pow is the                             b2int (𝐵 1,1
                                                                                                     0,𝑥             0,𝑥
                                                                                                         , . . . , 𝐵 1,𝜇 ) − b2int (𝐵 1,1
                                                                                                                                      4,𝑥              4,𝑥  2
                                                                                                                                          , . . . , 𝐵 1,𝜇  )
                                                                                           + b2int (𝐵 2,1 , . . . , 𝐵 2,𝜇 ) − (b2int (𝐵 2,1 , . . . , 𝐵 2,𝜇 ) + 1)
validity predicate, written in terms of enriched polynomials, giving                                   0,𝑥             0,𝑥               4,𝑥              4,𝑥        2
the condition that pow is an arity 4 matrix variable symbol with
                                                                                            + b2int (𝐵 3,1
                                                                                                       0,𝑥             0,𝑥
                                                                                                           , . . . , 𝐵 3,𝜇 )
rows pow𝑖 which encodes the power function, and where pow𝑖 (𝑋 )                                                                                                        
denotes an enriched polynomial. We let the entries of pow1 corre-                                                            ) ∗ b2int (𝐵 3,1
                                                                                                         0,𝑥             0,𝑥              4,𝑥             4,𝑥     2
                                                                                               −b2int (𝐵 1,1 , . . . , 𝐵 1,𝜇                  , . . . , 𝐵 3,𝜇 )
spond to bases, pow2 correspond to exponents, pow3 correspond to
the function output, and pow4 correspond to pointers. Set                       The condition 𝛽 F (mkQ𝑥F ⟨𝜙 pow ⟩) = 0 is equivalent to saying that
         baseCase(𝑋 ) = (pow2 (𝑋 ) = 0) ∧ (pow3 (𝑋 ) = 1),                    when 𝛽 F replaces the 𝐵 0,𝑥 with π𝜈 ∅b 𝑓˜𝑖
                                                                                                             𝑖,𝜈           ( ∅b 𝑥) and the 𝐵 4,𝑥 with
                                                                                                                                  𝜍 ( pow )                       𝑖,𝜈
             indStep(𝑋 ) = pow1 (𝑋 ) = pow1 (pow4 (𝑋 ))       ∧                                                                                            0,𝑥
                                                                              π𝜈 ∅b 𝑓˜𝜍𝑖 ( pow ) ( ∅b 𝑓˜𝜍4( pow ) ( ∅b 𝑥)), that is when 𝛽 F replaces the 𝐵𝑖,𝜈 with
                               pow2 (𝑋 ) = pow2 (pow4 (𝑋 )) + 1 ∧                                           4,𝑥
                                                                              π𝜈 ∅b 𝜍 (pow) @𝑖,𝑥 and the 𝐵𝑖,𝜈    with π𝜈 ∅b 𝜍 (pow) @𝑖,𝜍 (pow) @4,𝑥 , we
                               pow3 (𝑋 ) = pow1 (𝑋 ) · pow3 (pow4 (𝑋 ))       obtain 0. Thus mkQ F ⟨𝜙 pow ⟩ has roots at the binary decompositions
                                                                                                   𝑥

                                                                              of (a subset of) the entries of 𝜍 (pow), if 𝜍 is a valid interpretation.
Then — using a chained-≤ shorthand for range checks — set
                                                                                 The final RELgp,Q instance, ignoring range checks for simplicity,
(𝜙 pow, 𝑅pow ) = baseCase(𝑋 ) ∨ indStep(𝑋 ), 1 ≤ pow4 ≤ len(pow)
                                                                          
                                                                              has Q = (mkQ𝑥F ⟨𝜙 pow ⟩)𝑥 ∈ [len(𝜍 (pow) ) ] and witness w = ( 𝑓˜𝜍𝑖 (C) )𝑖 ∈ [4] .
zk-SNARKs for First Order Logic                                                                                    Conference acronym ’XX, June 03–05, 2018, Woodstock, NY


   Arithmetising SK Combinator Reduction. We next consider zk-                              Then set
SNARKs for SK combinator reduction, a Turing-complete system
                                                                                                (𝜙 SK , 𝑅SK ) = Kred(𝑋 ) ∨ Sred(𝑋 ) ∨ Id(𝑋 ) ∨ Par(𝑋 ) ∨ Tran(𝑋 ),
of computation. This allows us to take as an instance any Turing-
                                                                                                               1 ≤ SK6 ≤ len(SK) ∧ 1 ≤ SK7 ≤ len(SK)
                                                                                                                                                      
complete computation, compiled to SK combinator calculus, and
run a zk-SNARK on the statement expressed in our FOL semantics                                See [15, Lemma 3.9.10] for a proof that (𝜙 SK, 𝑅SK ) does in fact
to allow a prover to prove knowledge of witnesses to properties of                          encode SK combinator reduction.
such computations.                                                                            Applying the transform of Figure 2 to 𝜙 SK , we obtain an enriched
   The interested reader can find more on SK combinator reduction                           polynomial instance in
in [15, Section 3.9]. A nice summary of the benefits of combinator
reduction, and how it relates to other computational models, is                                              
                                                                                                                                 𝜙 = 𝜙 SK, 𝑅 = 𝑅SK, C = SK       
                                                                                                                                                                  
                                                                                                   RelEP
                                                                                                             
                                                                                                                                                                 
                                                                                                                                                                  
contained in the early pages of [24]; see also [11]. Furthermore a                                    gp =     ((⟨𝜙⟩, 𝑅), 𝜍)      𝜍 (C) ∈ M8×len(𝜍 (C) ) (N)
                                                                                                                                                                 
zk-SNARK-friendly treatment of SK combinators is the proposed                                                
                                                                                                                                 C ⊨𝜍 𝜙; 𝑅                       
                                                                                                                                                                  
EDEN system [1].12                                                                          where 𝑅SK contains the range checks 1 ≤ SK6 ≤ len(SK) and 1 ≤
   We begin by defining the Cantor pairing function:                                        SK7 ≤ len(SK), and
   Definition 5.2. Define a Cantor pairing map13                                            ⟨𝜙 SK ⟩ = SK1 (𝑋 ) − ⟨⟨1, SK2 (𝑋 )⟩, SK4 (𝑋 )⟩
                                                                                                                                           2

                      ⟨·, ·⟩ ′ : N × N → N                                                            ∗ (SK1 (𝑋 ) − ⟨⟨⟨0, SK3 (𝑋 )⟩, SK4 (𝑋 )⟩, SK5 (𝑋 )⟩) 2
                    ⟨𝑥, 𝑦⟩ ′ = (𝑥 + 𝑦) ∗ (𝑥 + 𝑦 + 1) + 2 ∗ 𝑥                                                                                                             
                                                                                                         + (SK2 (𝑋 ) − ⟨⟨SK3 (𝑋 ), SK5 (𝑋 )⟩, ⟨SK4 (𝑋 ), SK5 (𝑋 )⟩⟩) 2
   We now arithmetise SK combinator reduction. We first define
a relation, where 𝜙 SK is a validity predicate, giving the condition                                  ∗ (SK1 (𝑋 ) − SK2 (𝑋 )) 2
that SK is a matrix variable symbol encoding combinator reduction:                                    ∗ (SK1 (𝑋 ) − ⟨SK1 (SK6 (𝑋 )), SK1 (SK7 (𝑋 ))⟩) 2
                 
                                       𝜙 = 𝜙 SK, 𝑅 = 𝑅SK, C = SK                
                                                                                                        + (SK2 (𝑋 ) − ⟨SK2 (SK6 (𝑋 )), SK2 (SK7 (𝑋 ))⟩) 2
     RelFOL
                 
                                                                                
                                                                                 
        gp =       ((𝜙, 𝑅), 𝜍)          𝜍 (C) ∈ Mar (C) ×len(𝜍 (C) ) (N)                                 + (SK8 (𝑋 ) − SK8 (SK6 (𝑋 )) − 1) 2
                                                                                
                                       C ⊨𝜍 𝜙; 𝑅                                
                                                                                                                                               
                                                                                                         + (SK8 (𝑋 ) − SK8 (SK7 (𝑋 )) − 1) 2
                                                                                
where SK is an arity 8 matrix with rows SK𝑖 and 𝜙 SK is defined as
follows, where SK𝑖 (𝑋 ) denotes an enriched polynomial and ⟨·, ·⟩ :=                                  ∗ (SK1 (𝑋 ) − SK1 (SK6 (𝑋 ))) 2
⟨·, ·⟩ ′ + 2, where ⟨·, ·⟩ ′ is Cantor pairing. Set                                                      + (SK2 (𝑋 ) − SK2 (SK7 (𝑋 ))) 2
    Kred(𝑋 ) = SK1 (𝑋 ) = ⟨⟨1, SK2 (𝑋 )⟩, SK4 (𝑋 )⟩,                                                     + (SK2 (SK6 (𝑋 )) − SK1 (SK7 (𝑋 ))) 2
     Sred(𝑋 ) = SK1 (𝑋 ) = ⟨⟨⟨0, SK3 (𝑋 )⟩, SK4 (𝑋 )⟩, SK5 (𝑋 )⟩ ∧                                       + (SK8 (𝑋 ) − SK8 (SK6 (𝑋 )) − 1) 2
                   SK2 (𝑋 ) = ⟨⟨SK3 (𝑋 ), SK5 (𝑋 )⟩, ⟨SK4 (𝑋 ), SK5 (𝑋 )⟩⟩,                              + (SK8 (𝑋 ) − SK8 (SK7 (𝑋 )) − 1) 2
                                                                                                                                               
        Id(𝑋 ) = SK1 (𝑋 ) = SK2 (𝑋 ),
                                                                                               using the transform of Figure 2.
      Par(𝑋 ) = SK1 (𝑋 ) = ⟨SK1 (SK6 (𝑋 )), SK1 (SK7 (𝑋 ))⟩ ∧                                  Applying mkQ𝑥F to ⟨𝜙 SK ⟩ we obtain the len(𝜍 (SK)) polynomials
                   SK2 (𝑋 ) = ⟨SK2 (SK6 (𝑋 )), SK2 (SK7 (𝑋 ))⟩ ∧                            that (partly) comprise the set Q for the instance of the relation upon
                   SK8 (𝑋 ) = SK8 (SK6 (𝑋 )) + 1 ∧                                          which Zinc-PIOP may be run.
                   SK8 (𝑋 ) = SK8 (SK7 (𝑋 )) + 1,
                                                                                            6     Conclusion
    Tran(𝑋 ) = SK1 (𝑋 ) = SK1 (SK6 (𝑋 ))             ∧
                                                                                            Related work: circuit languages and zkVMs. We discussed related
                   SK2 (𝑋 ) = SK2 (SK7 (𝑋 ))         ∧                                      work on arithmetisation in the Introduction; we now continue that
                   SK2 (SK6 (𝑋 )) = SK1 (SK7 (𝑋 ))          ∧                               discussion with some comment on, and comparison with, circuit
                   SK8 (𝑋 ) = SK8 (SK6 (𝑋 )) + 1 ∧                                          languages and zkVMs.
                                                                                               Circuit languages (think: Circom, Noir) allow programmers to
                   SK8 (𝑋 ) = SK8 (SK7 (𝑋 )) + 1
                                                                                            specify the behaviour of code in a manner suited for subsequent
12 To our knowledge [1] is not a peer-reviewed publication. However, if EDEN itself is      arithmetisation to constraint systems (for example R1CS).
correct then it is a developed and apparently practical zk-SNARK-friendly treatment            zkVMs (think: Cairo, RISC0) fix a machine model for computation,
of SK combinators (represented as Dyck words injected into strings of finite field          with a cryptographic proof layer on top with which to succinctly
elements). It may be worth quoting the authors on why this matters: “Most zkVMs
emulate the von Neumann architecture and must prove relations between a program’s
                                                                                            or in zero knowledge prove correctness of that computation; so
execution and its use of Random Access Memory. However, there are conceptually simpler      that arithmetisation for VM-based zk-SNARKs takes (high-level)
models of computation that are naturally modelled in a zk-SNARK yet are still practical     code to a circuit language to VM execution traces, which may then
for use.” Amen. With respect to that paper, our ‘zkVM’ is FOL itself, and in this Section
we show a simple but direct and effective way to encode SK combinator reduction             be arithmetised to a constraint system and finally input to the zk-
within it.                                                                                  SNARK of choice.
13 The Cantor pairing function bijects N × N with N and is equal to ⟨𝑥, 𝑦⟩ ′ /2. But this
                                                                                               Examples of zk-SNARKs for such systems include [29, 3, 35]; an
would require us to include fractions in our term language, which is a wrinkle which
we prefer to avoid for simplicity, since here we just need some injection that can be       example of a combinator-based (rather than von Neumann archi-
expressed as a polynomial.                                                                  tecture based) zkVM is in [1].
Conference acronym ’XX, June 03–05, 2018, Woodstock, NY                                                                                 Murdoch J. Gabbay and Andrew Mendelsohn


   For comparison, this paper does not introduce a new zkVM or                                     (3) Developing on this theme, transaction correctness, compliance
circuit-level language for compilation to zk-SNARK inputs. The                                         rules, and similar correctness assertions might be natural
arithmetised language of this work is logic itself; this operates at a                                 targets to be expressed in the framework in this paper.
higher level of abstraction.                                                                   Implementation and benchmarking of the above are natural next
   Now, we consider SK combinators as an example, and any com-                                 steps.18
putation performable on a Turing machine could be compiled to SK                                  We also plan to build a version of these ideas that works directly
combinator reduction and then fed into our example FOL-based zk-                               over finite fields. This may be particularly appealing to cryptogra-
SNARK. Therefore, we see a risk that a reader might latch onto this                            phers, who are used to this datatype.
computational example and conflate that example with the entire                                   Such a finite field-based scheme is certainly possible, but we
paper. For the avoidance of doubt, that would miss the point! This                             should understand its value in a practical context. Much program-
paper gives a compositional arithmetisation of an expressive general                           ming naturally occurs over rational and integer datatypes (e.g. the
purpose first-order mathematical logic specification language, over                            reader’s bank balance, velocity, and timestamp are natural numbers
finite integer models.14 To our knowledge, this is a novel concept.                            not finite field elements), and using a finite field back end can create
                                                                                               a data representation mismatch.
Concluding remarks and future work. We have provided an arith-
                                                                                                  This mismatch can easily be overcome, but the question is where
metisation of an expressive first-order logic over finite models. We
                                                                                               we put the engineering effort and the audit risk of doing so. These
can take any predicate expressible in the syntax of Figure 1 and
                                                                                               are design questions, and various design possibilities exist: Zinc
convert knowledge of a valid witness (i.e. interpretation) to an input
                                                                                               pushes engineering effort onto the cryptographic back end; a finite
instance for a zk-SNARK. Thanks to our use of Zinc, we do not
                                                                                               field version of this work would push the engineering effort more
have to rewrite these instances to equivalent instances over finite
                                                                                               towards the user; another option is to offer a standard abstraction
fields (we comment on arithmetisation to finite fields below).
                                                                                               in-between the user and the cryptographic back end.19
   We gave two examples of our arithmetisation, including SK com-
                                                                                                  There is no one right answer here, and the trade-offs may depend
binator reduction. Since SK combinators are Turing-complete, this
                                                                                               on use-case and may also change with time as technology evolves.
shows that our system is powerful enough to convert knowledge
                                                                                               There is a design space here, for us to explore.
of the output of any computation15 on a Turing machine into zk-
SNARK-compatible form, for a zero knowledge proving system.16
                                                                                               References
   The maths in this paper bridges the gap between FOL in Figure 1
                                                                                                [1]   Logan Allen, Brian Klatt, Philip Quirk, and Yaseen Shaikh. 2023. EDEN - a
— a standard and expressive mathematical language — and the                                           practical, SNARK-friendly combinator VM and ISA. Cryptology ePrint Archive,
concrete polynomials of a zk-SNARK like Zinc. This opens up                                           Paper 2023/1021. (2023). https://eprint.iacr.org/2023/1021.
                                                                                                [2]   S. Angel, E. Ioannidis, E. Margolin, S. Setty, and J. Woods. 2024. Reef: fast
interesting possibilities for implementation in future work:                                          succinct Non-Interactive Zero-Knowledge Regex proofs. In Proceedings of the
    (1) We can insist on cryptographic certification of correct be-                                   33rd USENIX Security Symposium. USENIX Association, (Aug. 2024), 3801–3818.
                                                                                                      doi: 10.5555/3698900.3699113.
        haviour. ‘Just’ write a FOL predicate describing your desired                           [3]   A. Arun, S. Setty, and J. Thaler. 2024. Jolt: snarks for virtual machines via
        notion of correctness,17 and put your black-box (and possibly                                 lookups. In EUROCRYPT 2024 (LNCS). M. Joye and G. Leander, (Eds.) Vol. 14656.
                                                                                                      Springer Nature Switzerland, 3–33. doi: 10.1007/978-3-031-58751-1_1.
        adversarial) process in a wrapper that insists on a succinct                            [4]   Lennart Augustsson. 2024. MicroHs: a small compiler for Haskell. In Proceedings
        cryptographic proof of correctness, before accepting its pro-                                 of the 17th ACM SIGPLAN International Haskell Symposium (Haskell 2024). As-
        posed output.                                                                                 sociation for Computing Machinery, Milan, Italy, 120–124. isbn: 9798400711022.
                                                                                                      doi: 10.1145/3677999.3678280.
    (2) Because FOL itself can directly express computation, it allows                          [5]   J. Barwise. 1977. An introduction to first-order logic. In Handbook of Mathe-
        us to design computation at the very high level of logic,                                     matical Logic. Jon Barwise, (Ed.) North Holland, 5–46. isbn: 0444863885.
        which in some applications may save us from having to                                   [6]   E. Ben-Sasson, A. Chiesa, and N. Spooner. 2016. Interactive oracle proofs.
                                                                                                      In TCC 2016 (LNCS). M. Hirt and A. Smith, (Eds.) Vol. 9986. Springer Berlin
        write code targeted at a specific virtual machine or circuit.                                 Heidelberg, 31–60. doi: 10.1007/978-3-662-53644-5_2.
                                                                                                [7]   Eli Ben-Sasson, Alessandro Chiesa, Daniel Genkin, Eran Tromer, and Madars
14 Subtlety note: the arithmetisation in this paper is of logical validity, not logical
                                                                                                      Virza. 2013. SNARKs for C: verifying program executions succinctly and in
                                                                                                      zero knowledge. In CRYPTO 2013 (LNCS). Ran Canetti and Juan A. Garay, (Eds.)
derivability. This matters and gives our logic significant extra power. For example: it               Vol. 8043. Springer Berlin Heidelberg, 90–108. doi: 10.1007/978-3-642-40084-1
makes it easy for us to include reification as reify(𝜙 ) in Figure 1, interpreted ‘for free’          _6.
as a no-op ⟨reify(𝜙 ) ⟩𝜍𝑥 = ⟨𝜙 ⟩𝜍𝑥 in Figure 2. The focus in this paper is on building a        [8]   A. R. Block, Z. Fang, J. Katz, J. Thaler, H. Waldner, and Y. Zhang. 2024. Field-
zk-SNARK infrastructure and we do not explore the particular FOL language used in                     agnostic SNARKs from expand-accumulate codes. In CRYPTO 2024 (LNCS). L.
this paper for its own sake, but it is in and of itself an extremely interesting logical              Reyzin and D. Stebila, (Eds.) Vol. 14929. Springer Nature Switzerland, 276–307.
object.                                                                                               doi: 10.1007/978-3-031-68403-6_9.
15 Pedant point: any finite computation, because our witnesses are finite. But this is
                                                                                                [9]   B. Bünz, B. Fisch, and A. Szepieniec. 2020. Transparent SNARKs from dark com-
fine: correctness of finite logic and computation is what we want to cryptographically                pilers. In EUROCRYPT 2020 (LNCS). A. Canteaut and Y. Ishai, (Eds.) Vol. 12105.
prove.                                                                                                Springer International Publishing, 677–706. doi: 10.1007/978-3-030-45721-1_2
16 It is known to logicians that FOL is powerful, convenient, and versatile. However,                 4.
non-logicians sometimes hold misconceptions that FOL is logic, and logic is either             [10]   M. Campanelli and M. Hall-Andersen. 2024. Fully succinct arguments over
undecidable (which means you can’t use it to decide anything) or theoretical (which                   the integers from first principles. Cryptology ePrint Archive, Paper 2024/1548.
means you can’t use it to do anything useful) or not-programming (which means both                    (2024). https://eprint.iacr.org/2024/1548.
of the above and has no users). Doing exponentials and SK combinators is a way to
                                                                                               18 A prototype implementation of the core building blocks of our arithmetisation is
formally address these misapprehensions: these two small examples are decidable,
practical, programmable, and they have nonempty userbases. Larger examples are also            available at https://anonymous.4open.science/r/zk-SNARKs-for-First-Order-Logic-
possible, just prolix.                                                                         2A41/README.md. It was hand-coded by a human.
17We put ‘just’ in scare quotes here because writing this predicate is the problem of          19 Like Cairo’s (un)signed integer libraries: https://rareskills.io/post/cairo-integers.

formal specification, which is non-trivial. But that is not a bug; it is a business and
consulting opportunity.
zk-SNARKs for First Order Logic                                                                                     Conference acronym ’XX, June 03–05, 2018, Woodstock, NY


[11]   T. J.W. Clarke, P. J.S. Gladstone, C. D. MacLean, and A. C. Norman. 1980. SKIM -     [35]   A. Zapico, V. Buterin, D. Khovratovich, M. Maller, A. Nitulescu, and M. Simkin.
       the S, K, I reduction machine. In Proceedings of the 1980 ACM Conference on LISP            2022. Caulk: lookup arguments in sublinear time. In Proceedings of the 2022 ACM
       and Functional Programming (LFP ’80). Association for Computing Machinery,                  SIGSAC Conference on Computer and Communications Security. Association for
       Stanford University, California, USA, 128–135. doi: 10.1145/800087.802798.                  Computing Machinery, (Nov. 2022), 3121–3134. doi: 10.1145/3548606.3560646.
[12]   B. E. Diamond and J. Posen. 2025. Succinct arguments over towers of binary           [36]   H. Zeilberger, B. Chen, and B. Fisch. 2024. Basefold: efficient field-agnostic
       fields. In EUROCRYPT 2025 (LNCS). S. Fehr and P.-A. Fouque, (Eds.) Vol. 15604.              polynomial commitment schemes from foldable codes. In CRYPTO 2024 (LNCS).
       Springer Nature Switzerland, 93–122. doi: 10.1007/978-3-031-91134-7_4.                      L. Reyzin and D. Stebila, (Eds.) Vol. 14929. Springer Nature Switzerland, Cham,
[13]   W. Ewald. 2019. The Emergence of First-Order Logic. In The Stanford Ency-                   138–169. doi: 10.1007/978-3-031-68403-6_5.
       clopedia of Philosophy. (Spring 2019 ed.). Edward N. Zalta, (Ed.) Metaphysics
       Research Lab, Stanford University.
[14]   Murdoch J. Gabbay. 2024. Arithmetisation of computation via polynomial               A      Open Science
       semantics for first-order logic. Cryptology ePrint Archive, Paper 2024/954.          To provide proof-of-concept for this work, we provide an imple-
       (2024). https://eprint.iacr.org/archive/2024/954/20240627:160807.
[15]   Murdoch J. Gabbay. 2025. Arithmetising logic: polynomial semantics of FOL.           mentation of two key results:
       Journal of Applied Logics, 12, 6, (Oct. 2025). (direct download). https://www.col       (1) We provide an implementation of the transform from FOL
       legepublications.co.uk/ifcolog/?00074.
[16]   A. Gabizon, Z. J. Williamson, and O. Ciobotaru. 2019. PLONK: permutations                   predicates 𝜙 to multivariate polynomials mkQ𝑥F ⟨𝜙⟩ obtained
       over Lagrange-bases for oecumenical noninteractive arguments of knowledge.                  by composing the transforms of Figure 2 and Figure 4.
       Cryptology ePrint Archive, Paper 2019/953. (2019). https://eprint.iacr.org/2019
       /953.
                                                                                               (2) We provide an implementation of the evaluation function 𝛽 F
[17]   Chaya Ganesh, Anca Nitulescu, and Eduardo Soria-Vazquez. 2023. Rinocchio:                   on the resulting multivariate polynomials mkQ𝑥F ⟨𝜙⟩, given
       SNARKs for ring arithmetic. J. Cryptol., 36, 4, (Oct. 2023). doi: 10.1007/s00145-           range-checked witness data.
       023-09481-3.
[18]   A. Garreta, H. Waldner, I. Vlasov, K. Hristova, L. Dall’Ava, M. Čupić, and M.        The implementation of item (1) is given for several examples defined
       Klein. 2025. Zinc: succinct arguments with small arithmetization overheads           in FOL. These include predicates corresponding to the standard
       from IOPs of proximity to the integers. In CRYPTO 2025 (LNCS). Y. Tauman
       Kalai and S. F. Kamara, (Eds.) Vol. 16006. Citations from [18] refer to the          inductive definition of the power function, to a more efficient power
       full version, available at https://eprint.iacr.org/2025/316. Springer Nature         function, to factorials, and to Fibonacci numbers. The implementa-
       Switzerland, 259–291. doi: 10.1007/978-3-032-01907-3_9.
[19]   A. Golovnev, J. Lee, S. Setty, J. Thaler, and R. S. Wahby. 2023. Brakedown:
                                                                                            tion of item (2) applies to each of the four stated examples.
       linear-time and field-agnostic SNARKs for R1CS. In CRYPTO 2023 (LNCS). H.               The code is available at https://anonymous.4open.science/r/zk-
       Handschuh and A. Lysyanskaya, (Eds.) Vol. 14082. Springer Nature Switzerland,        SNARKs-for-First-Order-Logic-2A41/README.md.
       193–226. doi: 10.1007/978-3-031-38545-2_7.
[20]   J. Groth. 2016. On the size of pairing-based non-interactive arguments. In
       EUROCRYPT 2016 (LNCS). M. Fischlin and J.-S. Coron, (Eds.) Vol. 9666. Springer       B      Ethical Considerations
       Berlin Heidelberg, 305–326. doi: 10.1007/978-3-662-49896-5_11.
[21]   K. Jiang, D. Chait-Roth, Z. DeStefano, M. Walfish, and T. Wies. 2023. Less is        The work in this paper is theoretical and mathematical: it does not
       more: refinement proofs for probabilistic proofs. In 2023 IEEE Symposium on          involve human subjects, personal data, private datasets, deployed
       Security and Privacy (SP), 1112–1129. doi: 10.1109/SP46215.2023.10179393.            systems, live experiments, vulnerability discovery, or malware.
[22]   M. Kohlweiss, M. Pancholi, and A. Takahashi. 2023. How to compile polynomial
       IOP into simulation-extractable SNARKs: a modular approach. In Theory of                As with other privacy-preserving technologies, it is possible to
       Cryptography (LNCS). G. Rothblum and H. Wee, (Eds.) Vol. 14371. Springer             exploit the ideas in this paper for unethical purposes. Such tools
       Nature Switzerland, 486–512. doi: 10.1007/978-3-031-48621-0_17.
[23]   J. Liang, D. Hu, P. Wu, Y. Yang, Q. Shen, and Z. Wu. 2025. SoK: understanding
                                                                                            could be incorporated into systems that conceal unlawful conduct,
       zk-SNARKs: the gap between research and practice. In Proceedings of the 34th         obscure accountability, or frustrate legitimate auditing. Further-
       USENIX Security Symposium Article 108. USENIX Association, USA, 20 pages.            more, incorrect deployment of cryptographic systems can harm
       doi: 10.5555/3766078.3766186.
[24]   J. Nicklisch-Franken and R. Feizerakhmanov. 2024. Massimult: a novel parallel        honest users: mistakes in implementations, unsound parameter
       cpu architecture based on combinator reduction. (2024). arXiv: 2412.02765            choices, or misunderstood threat models could lead to invalid proofs
       [cs.DC].                                                                             being accepted, privacy failures, financial loss, or misplaced trust.
[25]   A. Nitulescu. 2020. Zk-SNARKs: a gentle introduction. (2020). https://www.di
       .ens.fr/~nitulesc/files/Survey-SNARKs.pdf.                                           Additionally, high-level logical specifications may give users an un-
[26]   M. Orrù, G. Kadianakis, M. Maller, and G. Zaverucha. 2025. Beyond the circuit:       warranted sense that a policy or compliance requirement has been
       how to minimize foreign arithmetic in ZKP circuits. IACR Communications in
       Cryptology, 2, 1, (Apr. 8, 2025). doi: 10.62056/an-4c3c2h.
                                                                                            completely captured, when the complexity of real-world application
[27]   B. Parno, J. Howell, C. Gentry, and M. Raykova. 2013. Pinocchio: nearly practical    prevents this from being the case.
       verifiable computation. In IEEE Symposium on Security and Privacy 2013. Vol. 59.        We mitigate these risks by presenting our work as a mathematical
       (May 2013), 238–252. doi: 10.1109/SP.2013.47.
[28]   S. Setty, J. Thaler, and R. Wahby. 2023. Customizable constraint systems for         construction rather than as a production-ready system. We state our
       succinct arguments. Cryptology ePrint Archive, Paper 2023/552. (2023). https:        assumptions and the scope of the construction, providing abstract
       //eprint.iacr.org/2023/552.                                                          (rather than real-world) examples. We do not disclose vulnerabilities
[29]   S. Setty, J. Thaler, and R. Wahby. 2024. Unlocking the lookup singularity with
       lasso. In EUROCRYPT 2024 (LNCS). M. Joye and G. Leander, (Eds.) Vol. 14656.          or provide attack procedures against real systems. For these reasons
       Springer Nature Switzerland, 180–209. doi: 10.1007/978-3-031-58751-1_7.              we believe open publication is appropriate.
[30]   J. Thaler. 2022. Proofs, Arguments, and Zero-Knowledge. Foundations and Trends®
       in Privacy and Security. Vol. 4. Now Publishers, (Jan. 2022). doi: 10.1561/978163
                                                                                               We encourage any implementation intended for real-world use
       8281252.                                                                             based on our ideas to undergo independent cryptographic auditing
[31]   Urbit Systems Technical Journal. 2018. Nock. https : / / nock . is / intro . html.   and an application-specific policy review. In particular, applications
       Accessed 15 April 2026. (2018).
[32]   R. S. Wahby, I. Tzialla, A. Shelat, J. Thaler, and M. Walfish. 2018. Doubly-         involving compliance, regulation, or user rights should treat the
       efficient zkSNARKs without trusted setup. In 2018 IEEE Symposium on Security         FOL specification solely as a formal model of a policy and not as a
       and Privacy (SP), 926–943. doi: 10.1109/SP.2018.00060.                               substitute for legal or ethical judgment.
[33]   Y. Wei, X. Zhang, and Y. Deng. 2025. Transparent SNARKs over Galois rings.
       In PKC 2025 (LNCS). T. Jager and J. Pan, (Eds.) Vol. 15674. Springer Nature
       Switzerland, 418–451. doi: 10.1007/978-3-031-91820-9_14.
[34]   Z. Wu, X. Zhang, Y. Deng, Y. Wei, Z. Zhang, and L. Yang. 2025. Polylogarithmic
       polynomial commitment scheme over Galois rings. In ESORICS 2025. Springer-
       Verlag, 400–420. doi: 10.1007/978-3-032-07891-9_21.
```
