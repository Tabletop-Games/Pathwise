# WorkManager / Room reflection keep rules
# Room creates database implementations via reflection in Room.databaseBuilder()
-keep class * extends androidx.room.RoomDatabase {
    public <init>();
}
