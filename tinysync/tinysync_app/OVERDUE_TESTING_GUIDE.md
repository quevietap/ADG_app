# 🧪 How to Test if Overdue Trips System Works

## 🔍 **Quick Visual Checks** (Immediate)

### 1. **App Launch Verification**
```
✅ Check console logs when app starts:
   - Look for: "🕒 Initializing Overdue Trip Service..."
   - Look for: "✅ Overdue Trip Service initialized"
```

### 2. **UI Integration Check**
- Open any trips list page
- Look for **red "OVERDUE" badges** on trip cards
- Check if **"Remind Driver" button** appears on overdue trips
- Verify overdue trips show **warning icons** 🚨

---

## 🛠️ **Manual Testing Steps**

### Test 1: **Create an Overdue Trip**
1. **Create a test trip** with:
   - Start time: **2 hours ago**
   - Status: `assigned` or `in_progress`
2. **Wait 15 minutes** (system checks every 15 min)
3. **Expected results**:
   - Trip shows red "OVERDUE" badge
   - Driver gets push notification
   - Console shows: `"🔍 Checking for overdue trips..."`

### Test 2: **Remind Driver Function**
1. Find an overdue trip
2. Click **"Remind Driver"** button
3. **Expected results**:
   - Success message appears
   - Driver receives reminder notification
   - Console shows: `"✅ Reminder sent to driver"`

### Test 3: **Database Logging**
```sql
-- Check if notifications are being logged
SELECT * FROM notifications 
WHERE notification_type IN ('trip_overdue', 'trip_reminder') 
ORDER BY created_at DESC LIMIT 10;

-- Check if trips are being updated
SELECT id, trip_ref_number, last_overdue_notification_sent 
FROM trips 
WHERE last_overdue_notification_sent IS NOT NULL;
```

---

## 📱 **Live Testing Scenarios**

### Scenario A: **Not Started Trip**
```
Setup: Create trip with start_time = 1 hour ago
Status: 'assigned'
Expected: Driver gets notification "Trip overdue, please start"
```

### Scenario B: **Long Running Trip**
```
Setup: Create trip with end_time = 2 days ago
Status: 'in_progress'  
Expected: Driver gets "Trip taking too long" notification
```

### Scenario C: **Operator Notifications**
```
Setup: Trip overdue for 30+ minutes
Expected: Operators receive "Driver hasn't started" alert
```

---

## 🔧 **Debug Console Commands**

### Enable Debug Mode
```dart
// In overdue_trip_service.dart, add this to _checkForOverdueTrips():
print('📊 Found ${overdueTrips.length} overdue trips');
for (final trip in overdueTrips) {
  print('⚠️ Trip ${trip['trip_ref_number']} overdue since ${trip['start_time']}');
}
```

### Force Check (for testing)
```dart
// Call this manually to trigger immediate check:
OverdueTripService()._checkForOverdueTrips();
```

---

## 📊 **Monitoring Dashboard**

### Real-time Logs to Watch:
```
🕒 Initializing Overdue Trip Service...        [✅ Service Started]
🔍 Checking for overdue trips...               [✅ Monitoring Active]
📊 Found X overdue trips                       [✅ Detection Working]  
✅ Overdue notification sent to driver         [✅ Notifications Sent]
✅ Reminder sent to driver                     [✅ Reminders Working]
❌ Error checking overdue trips: [error]       [❌ Issue Found]
```

### Database Tables to Monitor:
- `trips` → Check `last_overdue_notification_sent` field
- `notifications` → Look for `trip_overdue` and `trip_reminder` types
- `users` → Verify `fcm_token` exists for push notifications

---

## 🚨 **Common Issues & Solutions**

### Issue 1: **No Overdue Detection**
```
Problem: No trips showing as overdue
Check: 
- Timer is running? (Console shows periodic checks)
- Trip start_time is actually in the past
- Trip status is 'assigned' or 'in_progress'
```

### Issue 2: **No Push Notifications**
```
Problem: Notifications not reaching devices
Check:
- FCM tokens exist in users table
- Firebase configuration is correct
- Device notification permissions enabled
```

### Issue 3: **Remind Button Not Working**
```
Problem: Remind button doesn't send notifications
Check:
- Console for "✅ Reminder sent to driver" message
- PushNotificationService methods are working
- Driver has valid FCM token
```

---

## 🎯 **Success Criteria Checklist**

### ✅ **System is Working If:**
- [ ] App logs show service initialization
- [ ] Overdue trips display red badges in UI
- [ ] Periodic checking runs every 15 minutes
- [ ] Push notifications reach devices
- [ ] Remind button sends notifications
- [ ] Database records notification history
- [ ] No compilation errors in console

### ❌ **System Needs Fix If:**
- [ ] No console logs appear
- [ ] Overdue trips show normal badges
- [ ] No periodic checking logs
- [ ] Push notifications fail
- [ ] Remind button shows errors
- [ ] Database queries fail
- [ ] Compilation errors present

---

## 🚀 **Quick Test Command**

Run this to see immediate status:
```powershell
cd "d:\project1\Softdev\tinysync\tinysync_app"
flutter run --debug
# Then watch console for overdue service logs
```

---

**💡 Pro Tip:** The easiest way to test is to create a trip with a start time 2 hours ago and status 'assigned', then wait for the next 15-minute check cycle!