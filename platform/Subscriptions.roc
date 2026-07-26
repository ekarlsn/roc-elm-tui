Subscriptions(event) := {
    stdin : Try(Box(Str -> event), [NotSubscribed]),
}.{
}
