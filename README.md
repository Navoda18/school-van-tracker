# School Van Tracker

A beginner-built MVP of a school van tracking app.
Parents see the van live on a map, get a near-home alert and boarding
messages, and mark their child absent. Drivers start trips, send GPS,
and do a digital roll call.

## Features
- Login with Parent or Driver role (Supabase Auth)
- Driver: Start/End Trip, GPS every 5 seconds, roll call (Boarded/Dropped)
- Driver: absent children hidden, "N stops skipped" banner
- Parent: live map, "last updated" indicator, near-home alert
- Parent: mark absence (Morning / Afternoon / Full day) with a 6:00 AM cut-off
- Roll call works through weak signal and syncs automatically
- Row Level Security: each user sees only their own data

## Tech
Flutter, Supabase (Postgres, Auth, Realtime), flutter_map + OpenStreetMap, geolocator

## Setup
1. Install Flutter and clone this repo.
2. Create a Supabase project and run the SQL for the tables and policies.
3. Copy `lib/config.example.dart` to `lib/config.dart` and add your
   Supabase URL and anon key. Never commit `config.dart`.
4. Run `flutter pub get`, then `flutter run`.

## Test accounts
Create users in Supabase (Authentication, Users), link a child to a
parent and a driver in the `students` table, then log in.

## Known limits
- Tracking works only while the driver app is open on screen
- Alerts appear only while the parent app is open (no push yet)
- Near-home alert is calculated on the parent's phone
- Offline roll call taps are kept in memory only
- Roles are chosen at sign-up, and "Confirm email" is off (development only)

## What's next
- Background GPS and FCM push notifications
- NestJS + PostGIS backend with server-side geofencing
- Admin web portal (fleet, routes, fees, reports, trip replay)
- Route optimisation, NFC/QR roll call, masked calling

## Screenshots
Add images in `docs/screenshots/`.