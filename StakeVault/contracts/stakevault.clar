;; Stake Vault - Liquid Staking Protocol with Auto-Compounding

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-invalid-amount (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-cooldown-active (err u103))
(define-constant err-no-rewards (err u104))
(define-constant err-pool-full (err u105))
(define-constant err-below-minimum (err u106))
(define-constant err-above-maximum (err u107))
(define-constant err-invalid-duration (err u108))
(define-constant err-already-exists (err u109))
(define-constant err-not-found (err u110))
(define-constant err-paused (err u111))
(define-constant err-slashing-active (err u112))
(define-constant err-invalid-rate (err u113))

;; Data Variables
(define-data-var total-staked uint u0)
(define-data-var total-rewards uint u0)
(define-data-var reward-rate uint u100) ;; 1% = 100 basis points
(define-data-var compound-frequency uint u1440) ;; ~1 day in blocks
(define-data-var last-compound uint u0)
(define-data-var min-stake uint u100000) ;; 0.1 STX minimum
(define-data-var max-stake uint u100000000000) ;; 100k STX maximum
(define-data-var cooldown-period uint u10080) ;; ~7 days
(define-data-var protocol-fee uint u100) ;; 1% = 100 basis points
(define-data-var slashing-rate uint u0) ;; 0% initially
(define-data-var emergency-pause bool false)
(define-data-var total-shares uint u0)
(define-data-var share-price uint u1000000) ;; 1:1 initially

;; Data Maps
(define-map staker-info
    principal
    {
        staked-amount: uint,
        shares: uint,
        reward-debt: uint,
        last-action: uint,
        cooldown-start: uint,
        pending-unstake: uint,
        total-earned: uint,
        auto-compound: bool
    }
)

(define-map stake-locks
    principal
    {
        amount: uint,
        unlock-height: uint,
        lock-duration: uint,
        bonus-rate: uint
    }
)

(define-map reward-snapshots
    uint
    {
        total-rewards: uint,
        total-staked: uint,
        share-price: uint,
        timestamp: uint
    }
)

(define-map delegation-info
    principal
    {
        validator: (optional principal),
        delegation-amount: uint,
        commission-rate: uint,
        last-claim: uint
    }
)

(define-map validator-stats
    principal
    {
        total-delegated: uint,
        commission-earned: uint,
        performance-score: uint,
        active: bool
    }
)

;; Private Functions
(define-private (calculate-shares (amount uint))
    (if (is-eq (var-get total-shares) u0)
        amount
        (/ (* amount (var-get total-shares)) (var-get total-staked))
    )
)

(define-private (calculate-amount (shares uint))
    (if (is-eq (var-get total-shares) u0)
        shares
        (/ (* shares (var-get total-staked)) (var-get total-shares))
    )
)

(define-private (calculate-rewards (user principal))
    (match (map-get? staker-info user)
        staker
        (let ((share-value (calculate-amount (get shares staker)))
              (initial-value (get staked-amount staker)))
            (if (> share-value initial-value)
                (- share-value initial-value)
                u0
            )
        )
        u0
    )
)

(define-private (apply-lock-bonus (base-rate uint) (lock-duration uint))
    (let ((bonus (/ (* lock-duration u10) u10080))) ;; 0.1% per week
        (+ base-rate bonus)
    )
)

(define-private (distribute-rewards (amount uint))
    (if (> (var-get total-staked) u0)
        (let ((new-share-price (+ (var-get share-price) 
                                 (/ (* amount u1000000) (var-get total-staked)))))
            (var-set share-price new-share-price)
            (var-set total-rewards (+ (var-get total-rewards) amount))
            true
        )
        false
    )
)

(define-private (apply-slashing (amount uint))
    (let ((slash-amount (/ (* amount (var-get slashing-rate)) u10000)))
        (- amount slash-amount)
    )
)

(define-private (update-validator-stats (validator principal) (amount uint) (commission uint))
    (match (map-get? validator-stats validator)
        stats
        (map-set validator-stats validator
            (merge stats {
                total-delegated: (+ (get total-delegated stats) amount),
                commission-earned: (+ (get commission-earned stats) commission)
            }))
        (map-set validator-stats validator {
            total-delegated: amount,
            commission-earned: commission,
            performance-score: u100,
            active: true
        })
    )
)

;; Public Functions
(define-public (stake (amount uint))
    (let ((shares (calculate-shares amount)))
        (asserts! (not (var-get emergency-pause)) err-paused)
        (asserts! (>= amount (var-get min-stake)) err-below-minimum)
        (asserts! (<= amount (var-get max-stake)) err-above-maximum)
        (asserts! (>= (stx-get-balance tx-sender) amount) err-insufficient-balance)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (match (map-get? staker-info tx-sender)
            existing
            (map-set staker-info tx-sender
                (merge existing {
                    staked-amount: (+ (get staked-amount existing) amount),
                    shares: (+ (get shares existing) shares),
                    last-action: stacks-block-height
                }))
            (map-set staker-info tx-sender {
                staked-amount: amount,
                shares: shares,
                reward-debt: u0,
                last-action: stacks-block-height,
                cooldown-start: u0,
                pending-unstake: u0,
                total-earned: u0,
                auto-compound: false
            })
        )
        
        (var-set total-staked (+ (var-get total-staked) amount))
        (var-set total-shares (+ (var-get total-shares) shares))
        
        (ok shares)
    )
)

(define-public (stake-locked (amount uint) (lock-duration uint))
    (let ((shares (calculate-shares amount))
          (bonus-rate (apply-lock-bonus (var-get reward-rate) lock-duration)))
        
        (asserts! (not (var-get emergency-pause)) err-paused)
        (asserts! (>= amount (var-get min-stake)) err-below-minimum)
        (asserts! (>= lock-duration u1440) err-invalid-duration) ;; Min 1 day
        (asserts! (<= lock-duration u100800) err-invalid-duration) ;; Max 70 days
        (asserts! (>= (stx-get-balance tx-sender) amount) err-insufficient-balance)
        
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        
        (map-set stake-locks tx-sender {
            amount: amount,
            unlock-height: (+ stacks-block-height lock-duration),
            lock-duration: lock-duration,
            bonus-rate: bonus-rate
        })
        
        (match (map-get? staker-info tx-sender)
            existing
            (map-set staker-info tx-sender
                (merge existing {
                    staked-amount: (+ (get staked-amount existing) amount),
                    shares: (+ (get shares existing) shares),
                    last-action: stacks-block-height
                }))
            (map-set staker-info tx-sender {
                staked-amount: amount,
                shares: shares,
                reward-debt: u0,
                last-action: stacks-block-height,
                cooldown-start: u0,
                pending-unstake: u0,
                total-earned: u0,
                auto-compound: false
            })
        )
        
        (var-set total-staked (+ (var-get total-staked) amount))
        (var-set total-shares (+ (var-get total-shares) shares))
        
        (ok shares)
    )
)

(define-public (start-unstake (shares uint))
    (let ((staker (unwrap! (map-get? staker-info tx-sender) err-not-found)))
        
        (asserts! (>= (get shares staker) shares) err-insufficient-balance)
        (asserts! (is-eq (get cooldown-start staker) u0) err-cooldown-active)
        
        (map-set staker-info tx-sender
            (merge staker {
                cooldown-start: stacks-block-height,
                pending-unstake: shares
            }))
        
        (ok true)
    )
)

(define-public (complete-unstake)
    (let ((staker (unwrap! (map-get? staker-info tx-sender) err-not-found))
          (unstake-shares (get pending-unstake staker)))
        
        (asserts! (> unstake-shares u0) err-invalid-amount)
        (asserts! (> (get cooldown-start staker) u0) err-not-found)
        (asserts! (>= (- stacks-block-height (get cooldown-start staker)) 
                     (var-get cooldown-period)) err-cooldown-active)
        
        (let ((amount (calculate-amount unstake-shares))
              (final-amount (apply-slashing amount)))
            
            (try! (as-contract (stx-transfer? final-amount tx-sender tx-sender)))
            
            (map-set staker-info tx-sender
                (merge staker {
                    shares: (- (get shares staker) unstake-shares),
                    staked-amount: (- (get staked-amount staker) amount),
                    cooldown-start: u0,
                    pending-unstake: u0,
                    last-action: stacks-block-height
                }))
            
            (var-set total-staked (- (var-get total-staked) amount))
            (var-set total-shares (- (var-get total-shares) unstake-shares))
            
            (ok final-amount)
        )
    )
)

(define-public (claim-rewards)
    (let ((staker (unwrap! (map-get? staker-info tx-sender) err-not-found))
          (rewards (calculate-rewards tx-sender)))
        
        (asserts! (> rewards u0) err-no-rewards)
        
        (let ((fee (/ (* rewards (var-get protocol-fee)) u10000))
              (net-rewards (- rewards fee)))
            
            (try! (as-contract (stx-transfer? net-rewards tx-sender tx-sender)))
            
            (map-set staker-info tx-sender
                (merge staker {
                    reward-debt: (+ (get reward-debt staker) rewards),
                    total-earned: (+ (get total-earned staker) net-rewards),
                    last-action: stacks-block-height
                }))
            
            (ok net-rewards)
        )
    )
)

(define-public (compound-rewards)
    (let ((total-pending (var-get total-rewards)))
        
        (asserts! (>= (- stacks-block-height (var-get last-compound)) 
                     (var-get compound-frequency)) err-invalid-duration)
        (asserts! (> total-pending u0) err-no-rewards)
        
        (let ((compound-amount (/ (* (var-get total-staked) (var-get reward-rate)) u10000)))
            
            (distribute-rewards compound-amount)
            
            (map-set reward-snapshots stacks-block-height {
                total-rewards: (var-get total-rewards),
                total-staked: (var-get total-staked),
                share-price: (var-get share-price),
                timestamp: stacks-block-height
            })
            
            (var-set last-compound stacks-block-height)
            
            (ok compound-amount)
        )
    )
)

(define-public (delegate-to-validator (validator principal) (amount uint))
    (let ((staker (unwrap! (map-get? staker-info tx-sender) err-not-found)))
        
        (asserts! (<= amount (get staked-amount staker)) err-insufficient-balance)
        
        (map-set delegation-info tx-sender {
            validator: (some validator),
            delegation-amount: amount,
            commission-rate: u500, ;; 5% default
            last-claim: stacks-block-height
        })
        
        (update-validator-stats validator amount u0)
        
        (ok true)
    )
)

(define-public (toggle-auto-compound (enabled bool))
    (let ((staker (unwrap! (map-get? staker-info tx-sender) err-not-found)))
        
        (map-set staker-info tx-sender
            (merge staker {auto-compound: enabled}))
        
        (ok true)
    )
)

(define-public (emergency-withdraw)
    (let ((staker (unwrap! (map-get? staker-info tx-sender) err-not-found)))
        
        (asserts! (var-get emergency-pause) err-paused)
        
        (let ((amount (get staked-amount staker)))
            
            (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
            
            (map-delete staker-info tx-sender)
            
            (var-set total-staked (- (var-get total-staked) amount))
            (var-set total-shares (- (var-get total-shares) (get shares staker)))
            
            (ok amount)
        )
    )
)

;; Admin Functions
(define-public (set-reward-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= new-rate u1000) err-invalid-rate) ;; Max 10%
        (var-set reward-rate new-rate)
        (ok true)
    )
)

(define-public (set-slashing-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= new-rate u500) err-invalid-rate) ;; Max 5%
        (var-set slashing-rate new-rate)
        (ok true)
    )
)

(define-public (toggle-emergency-pause)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (var-set emergency-pause (not (var-get emergency-pause)))
        (ok (var-get emergency-pause))
    )
)

(define-public (update-limits (min uint) (max uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (< min max) err-invalid-amount)
        (var-set min-stake min)
        (var-set max-stake max)
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-staker-info (staker principal))
    (map-get? staker-info staker)
)

(define-read-only (get-stake-lock (staker principal))
    (map-get? stake-locks staker)
)

(define-read-only (get-pending-rewards (staker principal))
    (calculate-rewards staker)
)

(define-read-only (get-share-price)
    (var-get share-price)
)

(define-read-only (get-total-staked)
    (var-get total-staked)
)

(define-read-only (get-total-shares)
    (var-get total-shares)
)

(define-read-only (get-validator-stats (validator principal))
    (map-get? validator-stats validator)
)

(define-read-only (get-protocol-stats)
    {
        total-staked: (var-get total-staked),
        total-shares: (var-get total-shares),
        total-rewards: (var-get total-rewards),
        share-price: (var-get share-price),
        reward-rate: (var-get reward-rate),
        slashing-rate: (var-get slashing-rate),
        last-compound: (var-get last-compound),
        emergency-pause: (var-get emergency-pause)
    }
)

(define-read-only (calculate-unstake-amount (shares uint))
    (let ((amount (calculate-amount shares)))
        (apply-slashing amount)
    )
)