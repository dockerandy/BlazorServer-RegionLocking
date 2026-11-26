using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace BlazorServer.Locking.Models
{
    /// <summary>
    /// Represents the result of a lock operation
    /// </summary>
    public class LockResult
    {
        public bool Success { get; set; }
        public string Message { get; set; }
        public string LockedByUser { get; set; }
        public DateTime? LockExpiresAt { get; set; }
        public int RegionId { get; set; }
    }

    /// <summary>
    /// Represents a region lock state
    /// </summary>
    public class RegionLock
    {
        public int LockId { get; set; }
        public int RegionId { get; set; }
        public string LockedByUserId { get; set; }
        public string LockedByUserName { get; set; }
        public DateTime LockedAt { get; set; }
        public DateTime LockTimeout { get; set; }
        public string CircuitId { get; set; }
        public bool IsExpired => DateTime.UtcNow > LockTimeout;
    }

    /// <summary>
    /// Lock audit entry for tracking lock/unlock operations
    /// </summary>
    public class LockAuditEntry
    {
        public int AuditId { get; set; }
        public int RegionId { get; set; }
        public string UserId { get; set; }
        public string Action { get; set; } // LOCKED, UNLOCKED, EXPIRED
        public DateTime ActionTime { get; set; }
        public string Details { get; set; }
    }

    /// <summary>
    /// Region data model
    /// </summary>
    public class Region
    {
        public int RegionId { get; set; }
        public string RegionName { get; set; }
        public string RegionCode { get; set; }
        public string Manager { get; set; }
        public decimal Budget { get; set; }
        public DateTime CreatedDate { get; set; }
        public DateTime ModifiedDate { get; set; }
        public string ModifiedBy { get; set; }
        public bool IsActive { get; set; }
        
        // Lock state (not from DB, populated by service)
        public RegionLock CurrentLock { get; set; }
        public bool IsLockedByCurrentUser { get; set; }
        public bool IsLockedByOtherUser { get; set; }
    }
}
