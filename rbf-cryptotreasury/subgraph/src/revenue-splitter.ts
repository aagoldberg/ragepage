import { BigInt, Address, ethereum } from "@graphprotocol/graph-ts"
import {
  SplitExecuted,
  CapReached,
  SafetyRailTriggered,
  RevenueSplitter
} from "../../generated/RevenueSplitter/RevenueSplitter"
import {
  Deal,
  Split,
  DailyVolume,
  SafetyRailEvent,
  GlobalStats
} from "../../generated/schema"

const GLOBAL_STATS_ID = "global"
const SECONDS_PER_DAY = BigInt.fromI32(86400)

export function handleSplitExecuted(event: SplitExecuted): void {
  let deal = loadOrCreateDeal(event.address)
  
  // Create Split entity
  let splitId = event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  let split = new Split(splitId)
  split.deal = deal.id
  split.token = event.params.token
  split.totalAmount = event.params.toLenders.plus(event.params.toTreasury)
  split.toLenders = event.params.toLenders
  split.toTreasury = event.params.toTreasury
  split.totalPaidAfter = event.params.totalPaid
  split.blockNumber = event.block.number
  split.timestamp = event.block.timestamp
  split.transactionHash = event.transaction.hash
  split.save()
  
  // Update Deal
  deal.totalPaid = event.params.totalPaid
  deal.updatedAt = event.block.timestamp
  
  // Check if cap reached
  let contract = RevenueSplitter.bind(event.address)
  deal.isCapReached = contract.isCapReached()
  
  deal.save()
  
  // Update daily volume
  updateDailyVolume(deal.id, event.block.timestamp, event.params.toLenders)
  
  // Update global stats
  updateGlobalStats(event.params.toLenders)
}

export function handleCapReached(event: CapReached): void {
  let deal = loadOrCreateDeal(event.address)
  deal.isCapReached = true
  deal.totalPaid = event.params.totalPaid
  deal.updatedAt = event.block.timestamp
  deal.save()
  
  // Update global stats
  let stats = loadOrCreateGlobalStats()
  stats.completedDeals = stats.completedDeals.plus(BigInt.fromI32(1))
  stats.activeDeals = stats.activeDeals.minus(BigInt.fromI32(1))
  stats.save()
}

export function handleSafetyRailTriggered(event: SafetyRailTriggered): void {
  let deal = loadOrCreateDeal(event.address)
  
  let eventId = event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  let safetyEvent = new SafetyRailEvent(eventId)
  safetyEvent.deal = deal.id
  safetyEvent.reason = event.params.reason
  safetyEvent.blockNumber = event.block.number
  safetyEvent.timestamp = event.block.timestamp
  safetyEvent.transactionHash = event.transaction.hash
  safetyEvent.save()
}

function loadOrCreateDeal(address: Address): Deal {
  let deal = Deal.load(address.toHex())
  
  if (deal == null) {
    deal = new Deal(address.toHex())
    let contract = RevenueSplitter.bind(address)
    
    // Load contract data
    deal.splitter = address
    deal.treasury = contract.treasury()
    deal.lenderVault = contract.lenderVault()
    deal.shareBps = contract.shareBps()
    deal.repaymentCap = contract.repaymentCap()
    deal.dealStartTime = contract.dealStartTime()
    deal.dealEndTime = contract.dealEndTime()
    deal.dailyCap = contract.dailyCap()
    deal.transactionCap = contract.transactionCap()
    
    // Calculate advance amount from cap and share
    deal.advanceAmount = deal.repaymentCap.times(BigInt.fromI32(100)).div(BigInt.fromI32(135)) // Assuming 1.35x multiple
    
    // Initialize state
    deal.totalPaid = BigInt.fromI32(0)
    deal.isCapReached = false
    deal.isPaused = contract.isPaused()
    
    deal.createdAt = deal.dealStartTime
    deal.updatedAt = deal.dealStartTime
    
    // Update global stats
    let stats = loadOrCreateGlobalStats()
    stats.totalDeals = stats.totalDeals.plus(BigInt.fromI32(1))
    stats.activeDeals = stats.activeDeals.plus(BigInt.fromI32(1))
    stats.save()
  }
  
  return deal
}

function updateDailyVolume(dealId: string, timestamp: BigInt, amount: BigInt): void {
  let day = timestamp.div(SECONDS_PER_DAY)
  let volumeId = dealId + "-" + day.toString()
  
  let volume = DailyVolume.load(volumeId)
  if (volume == null) {
    volume = new DailyVolume(volumeId)
    volume.deal = dealId
    volume.day = day
    volume.volume = BigInt.fromI32(0)
    volume.transactionCount = BigInt.fromI32(0)
  }
  
  volume.volume = volume.volume.plus(amount)
  volume.transactionCount = volume.transactionCount.plus(BigInt.fromI32(1))
  volume.save()
}

function loadOrCreateGlobalStats(): GlobalStats {
  let stats = GlobalStats.load(GLOBAL_STATS_ID)
  
  if (stats == null) {
    stats = new GlobalStats(GLOBAL_STATS_ID)
    stats.totalDeals = BigInt.fromI32(0)
    stats.totalVolume = BigInt.fromI32(0)
    stats.totalPaid = BigInt.fromI32(0)
    stats.totalLenders = BigInt.fromI32(0)
    stats.activeDeals = BigInt.fromI32(0)
    stats.completedDeals = BigInt.fromI32(0)
  }
  
  return stats
}

function updateGlobalStats(amount: BigInt): void {
  let stats = loadOrCreateGlobalStats()
  stats.totalVolume = stats.totalVolume.plus(amount)
  stats.totalPaid = stats.totalPaid.plus(amount)
  stats.save()
}