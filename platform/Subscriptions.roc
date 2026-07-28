Subscriptions(event) := {
    stdin : Try(Box(List(U8) -> event), [NotSubscribed]),
}.{
}
