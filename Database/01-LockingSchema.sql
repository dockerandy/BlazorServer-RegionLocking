-- ============================================================
-- REGION LOCKING TABLE - Pessimistic Locking for Regions
-- ============================================================

CREATE TABLE RegionLocks (
    LockId NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    RegionId NUMBER NOT NULL,
    LockedByUserId VARCHAR2(255) NOT NULL,
    LockedByUserName VARCHAR2(255) NOT NULL,
    LockedAt TIMESTAMP DEFAULT SYSTIMESTAMP,
    LockTimeout TIMESTAMP NOT NULL,
    CircuitId VARCHAR2(255) NOT NULL,
    CONSTRAINT FK_RegionLocks_RegionId FOREIGN KEY (RegionId) REFERENCES Regions(RegionId) ON DELETE CASCADE,
    CONSTRAINT UQ_RegionLocks_RegionId UNIQUE (RegionId)
);

CREATE INDEX IDX_RegionLocks_UserId ON RegionLocks(LockedByUserId);
CREATE INDEX IDX_RegionLocks_CircuitId ON RegionLocks(CircuitId);
CREATE INDEX IDX_RegionLocks_LockTimeout ON RegionLocks(LockTimeout);

-- ============================================================
-- AUDIT LOG - Track Lock/Unlock Activities
-- ============================================================

CREATE TABLE LockAuditLog (
    AuditId NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    RegionId NUMBER NOT NULL,
    UserId VARCHAR2(255) NOT NULL,
    Action VARCHAR2(50) NOT NULL, -- 'LOCKED', 'UNLOCKED', 'EXPIRED'
    ActionTime TIMESTAMP DEFAULT SYSTIMESTAMP,
    Details VARCHAR2(500),
    CONSTRAINT FK_AuditLog_RegionId FOREIGN KEY (RegionId) REFERENCES Regions(RegionId) ON DELETE CASCADE
);

CREATE INDEX IDX_AuditLog_RegionId ON LockAuditLog(RegionId);
CREATE INDEX IDX_AuditLog_UserId ON LockAuditLog(UserId);
CREATE INDEX IDX_AuditLog_ActionTime ON LockAuditLog(ActionTime);

-- ============================================================
-- SAMPLE REGIONS TABLE
-- ============================================================

CREATE TABLE Regions (
    RegionId NUMBER PRIMARY KEY,
    RegionName VARCHAR2(100) NOT NULL UNIQUE,
    RegionCode VARCHAR2(10),
    Manager VARCHAR2(100),
    Budget NUMBER(12,2),
    CreatedDate TIMESTAMP DEFAULT SYSTIMESTAMP,
    ModifiedDate TIMESTAMP DEFAULT SYSTIMESTAMP,
    ModifiedBy VARCHAR2(255),
    IsActive CHAR(1) DEFAULT 'Y'
);

CREATE INDEX IDX_Regions_Name ON Regions(RegionName);

-- ============================================================
-- STORED PROCEDURES FOR LOCK MANAGEMENT
-- ============================================================

-- Acquire Lock on Region
CREATE OR REPLACE PROCEDURE SP_AcquireRegionLock(
    p_RegionId IN NUMBER,
    p_UserId IN VARCHAR2,
    p_UserName IN VARCHAR2,
    p_CircuitId IN VARCHAR2,
    p_LockTimeoutMinutes IN NUMBER DEFAULT 30,
    p_Success OUT NUMBER,
    p_Message OUT VARCHAR2
) AS
    v_ExistingLock RegionLocks%ROWTYPE;
BEGIN
    p_Success := 0;
    p_Message := '';
    
    -- Check if region exists
    BEGIN
        SELECT RegionId INTO v_ExistingLock.RegionId FROM Regions WHERE RegionId = p_RegionId;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_Success := 0;
            p_Message := 'Region not found.';
            RETURN;
    END;
    
    -- Check if already locked by another user
    BEGIN
        SELECT * INTO v_ExistingLock FROM RegionLocks WHERE RegionId = p_RegionId;
        
        IF v_ExistingLock.LockedByUserId != p_UserId THEN
            p_Success := 0;
            p_Message := 'Region is locked by ' || v_ExistingLock.LockedByUserName || ' until ' || TO_CHAR(v_ExistingLock.LockTimeout, 'YYYY-MM-DD HH24:MI:SS');
            RETURN;
        ELSE
            -- Same user, update timeout
            UPDATE RegionLocks 
            SET LockTimeout = SYSTIMESTAMP + NUMTODSINTERVAL(p_LockTimeoutMinutes, 'MINUTE')
            WHERE RegionId = p_RegionId;
            p_Success := 1;
            p_Message := 'Lock extended.';
            RETURN;
        END IF;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- No existing lock, create one
            INSERT INTO RegionLocks (RegionId, LockedByUserId, LockedByUserName, LockTimeout, CircuitId)
            VALUES (p_RegionId, p_UserId, p_UserName, SYSTIMESTAMP + NUMTODSINTERVAL(p_LockTimeoutMinutes, 'MINUTE'), p_CircuitId);
            
            INSERT INTO LockAuditLog (RegionId, UserId, Action, Details)
            VALUES (p_RegionId, p_UserId, 'LOCKED', 'Lock acquired by ' || p_UserName);
            
            p_Success := 1;
            p_Message := 'Lock acquired successfully.';
            COMMIT;
    END;
END SP_AcquireRegionLock;
/

-- Release Lock on Region
CREATE OR REPLACE PROCEDURE SP_ReleaseRegionLock(
    p_RegionId IN NUMBER,
    p_UserId IN VARCHAR2,
    p_Success OUT NUMBER,
    p_Message OUT VARCHAR2
) AS
    v_LockedByUserId VARCHAR2(255);
BEGIN
    p_Success := 0;
    p_Message := '';
    
    -- Check if lock exists and belongs to user
    SELECT LockedByUserId INTO v_LockedByUserId FROM RegionLocks WHERE RegionId = p_RegionId;
    
    IF v_LockedByUserId != p_UserId THEN
        p_Success := 0;
        p_Message := 'You do not own the lock on this region.';
        RETURN;
    END IF;
    
    -- Delete the lock
    DELETE FROM RegionLocks WHERE RegionId = p_RegionId;
    
    INSERT INTO LockAuditLog (RegionId, UserId, Action, Details)
    VALUES (p_RegionId, p_UserId, 'UNLOCKED', 'Lock released by ' || p_UserId);
    
    p_Success := 1;
    p_Message := 'Lock released successfully.';
    COMMIT;
    
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        p_Success := 0;
        p_Message := 'No lock found for this region.';
    WHEN OTHERS THEN
        p_Success := 0;
        p_Message := 'Error: ' || SQLERRM;
        ROLLBACK;
END SP_ReleaseRegionLock;
/

-- Check Lock Status
CREATE OR REPLACE FUNCTION FN_GetRegionLockStatus(p_RegionId IN NUMBER)
RETURN VARCHAR2 AS
    v_LockInfo VARCHAR2(500);
BEGIN
    SELECT LockedByUserName || ' (until ' || TO_CHAR(LockTimeout, 'HH24:MI:SS') || ')'
    INTO v_LockInfo
    FROM RegionLocks
    WHERE RegionId = p_RegionId AND LockTimeout > SYSTIMESTAMP;
    
    RETURN v_LockInfo;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN NULL;
END FN_GetRegionLockStatus;
/

-- Cleanup Expired Locks
CREATE OR REPLACE PROCEDURE SP_CleanupExpiredLocks AS
    v_ExpiredCount NUMBER := 0;
BEGIN
    DELETE FROM RegionLocks WHERE LockTimeout < SYSTIMESTAMP;
    
    v_ExpiredCount := SQL%ROWCOUNT;
    
    INSERT INTO LockAuditLog (RegionId, UserId, Action, Details)
    SELECT RegionId, 'SYSTEM', 'EXPIRED', 'Lock expired automatically'
    FROM RegionLocks WHERE LockTimeout < SYSTIMESTAMP;
    
    COMMIT;
    
    DBMS_OUTPUT.PUT_LINE('Cleaned up ' || v_ExpiredCount || ' expired locks.');
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error during cleanup: ' || SQLERRM);
        ROLLBACK;
END SP_CleanupExpiredLocks;
/

-- Release all locks for a circuit (when user disconnects)
CREATE OR REPLACE PROCEDURE SP_ReleaseCircuitLocks(p_CircuitId IN VARCHAR2) AS
    v_ReleasedCount NUMBER := 0;
BEGIN
    FOR lock_rec IN (SELECT RegionId, LockedByUserId FROM RegionLocks WHERE CircuitId = p_CircuitId)
    LOOP
        INSERT INTO LockAuditLog (RegionId, UserId, Action, Details)
        VALUES (lock_rec.RegionId, lock_rec.LockedByUserId, 'UNLOCKED', 'Circuit disconnected - automatic release');
        
        DELETE FROM RegionLocks WHERE RegionId = lock_rec.RegionId;
        v_ReleasedCount := v_ReleasedCount + 1;
    END LOOP;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Released ' || v_ReleasedCount || ' locks for circuit ' || p_CircuitId);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error releasing circuit locks: ' || SQLERRM);
        ROLLBACK;
END SP_ReleaseCircuitLocks;
/
