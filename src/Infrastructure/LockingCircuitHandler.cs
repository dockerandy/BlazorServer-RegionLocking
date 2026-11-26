using Microsoft.AspNetCore.Components.Server.Circuits;
using BlazorServer.Locking.Services;
using System.Threading.Tasks;

namespace BlazorServer.Locking.Infrastructure
{
    /// <summary>
    /// Custom Blazor Circuit Handler
    /// Automatically releases all locks when a user's circuit disconnects
    /// This handles the case when user closes browser or connection is lost
    /// </summary>
    public class LockingCircuitHandler : CircuitHandler
    {
        private readonly IRegionLockService _lockService;

        public LockingCircuitHandler(IRegionLockService lockService)
        {
            _lockService = lockService ?? throw new System.ArgumentNullException(nameof(lockService));
        }

        /// <summary>
        /// Called when a circuit is established (user connects)
        /// We don't need to do anything here, but circuit ID is available if needed
        /// </summary>
        public override Task OnCircuitOpenedAsync(Circuit circuit, CancellationToken cancellationToken)
        {
            System.Diagnostics.Debug.WriteLine($"[LockingCircuitHandler] Circuit opened: {circuit.Id}");
            return Task.CompletedTask;
        }

        /// <summary>
        /// Called when a circuit is disconnected (user closes browser, loses connection)
        /// Automatically releases all locks held by this circuit
        /// </summary>
        public override async Task OnCircuitClosedAsync(Circuit circuit, CancellationToken cancellationToken)
        {
            System.Diagnostics.Debug.WriteLine($"[LockingCircuitHandler] Circuit closed: {circuit.Id}");

            try
            {
                // Release all locks for this circuit
                bool success = await _lockService.ReleaseCircuitLocksAsync(circuit.Id);
                
                if (success)
                {
                    System.Diagnostics.Debug.WriteLine($"[LockingCircuitHandler] Successfully released all locks for circuit: {circuit.Id}");
                }
                else
                {
                    System.Diagnostics.Debug.WriteLine($"[LockingCircuitHandler] Failed to release locks for circuit: {circuit.Id}");
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[LockingCircuitHandler] Error releasing locks: {ex.Message}");
                // Don't throw - we want graceful degradation
            }

            await base.OnCircuitClosedAsync(circuit, cancellationToken);
        }

        /// <summary>
        /// Called when a circuit is unhandled exception
        /// Optionally clean up locks here as well
        /// </summary>
        public override async Task OnCircuitUnhandledExceptionAsync(Circuit circuit, Exception exception, CancellationToken cancellationToken)
        {
            System.Diagnostics.Debug.WriteLine($"[LockingCircuitHandler] Unhandled exception in circuit: {circuit.Id}, {exception.Message}");

            try
            {
                // Also release locks on unhandled exception
                await _lockService.ReleaseCircuitLocksAsync(circuit.Id);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine($"[LockingCircuitHandler] Error during exception cleanup: {ex.Message}");
            }

            await base.OnCircuitUnhandledExceptionAsync(circuit, exception, cancellationToken);
        }
    }
}
