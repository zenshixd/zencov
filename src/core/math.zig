pub fn min(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return if (a < b) a else b;
}
