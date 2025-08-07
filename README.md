# Stake Vault - Smart Contract Documentation

## Overview
Stake Vault is a liquid staking protocol offering auto-compounding rewards, locked staking bonuses, slashing protection, and validator delegation with tokenized positions.

## Problem Solved
- **Illiquid Staking**: Tokenized staking positions
- **Manual Compounding**: Automated reward reinvestment
- **Validator Risk**: Slashing protection mechanisms
- **Capital Efficiency**: Liquid staking derivatives

## Key Features

### Core Functionality
- Flexible and locked staking options
- Auto-compounding rewards
- Two-step unstaking with cooldown
- Slashing protection
- Validator delegation

### Staking Options
- **Flexible Staking**: Unstake anytime after cooldown
- **Locked Staking**: Higher rewards for time commitment
- **Auto-Compound**: Automatic reward reinvestment

## Contract Functions

### Staking Operations

#### `stake`
- **Parameters**: amount
- **Returns**: shares received
- **Requirements**: Min/max limits, not paused

#### `stake-locked`
- **Parameters**: amount, lock-duration
- **Returns**: shares with bonus
- **Effect**: Locks with bonus rewards

#### `start-unstake`
- **Parameters**: shares
- **Effect**: Initiates 7-day cooldown

#### `complete-unstake`
- **Returns**: amount after slashing
- **Requirements**: Cooldown period elapsed

### Reward Management

#### `claim-rewards`
- **Returns**: net rewards after fees
- **Effect**: Transfers accumulated rewards

#### `compound-rewards`
- **Returns**: compound amount
- **Effect**: Reinvests rewards for all stakers

#### `toggle-auto-compound`
- **Parameters**: enabled
- **Effect**: Opt-in for auto-compounding

### Delegation

#### `delegate-to-validator`
- **Parameters**: validator, amount
- **Effect**: Delegates stake to validator

### Admin Functions
- `set-reward-rate`: Adjust APY
- `set-slashing-rate`: Update slashing percentage
- `toggle-emergency-pause`: Emergency controls
- `update-limits`: Modify stake limits

### Read Functions
- `get-staker-info`: Complete staker details
- `get-pending-rewards`: Claimable rewards
- `get-share-price`: Current share value
- `calculate-unstake-amount`: Preview unstake value

## Usage Examples

```clarity
;; Stake 10 STX
(contract-call? .stake-vault stake u10000000)

;; Stake with 30-day lock for bonus
(contract-call? .stake-vault stake-locked 
    u10000000    ;; 10 STX
    u43200)      ;; 30 days

;; Start unstaking process
(contract-call? .stake-vault start-unstake u5000000)

;; Complete unstake after cooldown
(contract-call? .stake-vault complete-unstake)

;; Claim accumulated rewards
(contract-call? .stake-vault claim-rewards)

;; Enable auto-compounding
(contract-call? .stake-vault toggle-auto-compound true)
```

## Economic Model

### Share Calculation
```
shares = (amount * total_shares) / total_staked
value = (shares * total_staked) / total_shares
```

### Lock Bonus
- Base rate + 0.1% per week locked
- Maximum 70-day lock period

### Fees
- Protocol fee: 1% on rewards
- Slashing rate: 0-5% (adjustable)

## Security Features
1. **Two-Step Unstaking**: Prevents panic withdrawals
2. **Cooldown Period**: 7-day unstaking delay
3. **Slashing Protection**: Maximum 5% penalty
4. **Emergency Withdraw**: Crisis recovery
5. **Min/Max Limits**: Prevent abuse

## Staking Mechanics
- Share-based accounting
- Price appreciation through rewards
- Compound frequency: Daily
- Automatic distribution

## Deployment
1. Deploy contract
2. Set initial reward rate
3. Configure limits
4. Enable compounding
5. Add initial liquidity

## Testing Checklist
- Stake/unstake cycles
- Locked staking bonuses
- Cooldown enforcement
- Reward calculations
- Share price updates
- Slashing scenarios
- Emergency procedures

## Risk Management
- Minimum stake: 0.1 STX
- Maximum stake: 100,000 STX
- Cooldown period: 7 days
- Slashing cap: 5%
- Emergency pause available
