// Fetch slot configuration and update the page
async function loadSlotInfo() {
    try {
        const response = await fetch('/api/slot-info');
        const data = await response.json();

        // Update slot name
        const slotNameElement = document.getElementById('slot-name');
        slotNameElement.textContent = data.slot?.toUpperCase() || 'Unknown';

        // Update page title
        document.title = `Slot ${data.slot?.toUpperCase() || 'Unknown'} - Ready for Deployment`;

        // Update slot URL
        const slotUrlElement = document.getElementById('slot-url');
        slotUrlElement.href = data.slotUrl;
        slotUrlElement.textContent = data.slotUrl;

        // Update admin URL
        const adminUrlElement = document.getElementById('admin-url');
        adminUrlElement.href = data.adminUrl;

        // Update port
        const portElement = document.getElementById('port');
        portElement.textContent = data.port || 'unknown';

    } catch (error) {
        console.error('Failed to load slot info:', error);

        // Set fallback values
        document.getElementById('slot-name').textContent = 'Error';
        document.getElementById('slot-url').textContent = 'Failed to load';
        document.getElementById('admin-url').href = '#';
        document.getElementById('port').textContent = 'unknown';
    }
}

// Load slot info when the page loads
document.addEventListener('DOMContentLoaded', loadSlotInfo);
