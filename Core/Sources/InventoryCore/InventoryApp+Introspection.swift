import IntrospectionKit

extension InventoryApp: IntrospectionProviding {
    // ponytail: the root lends nothing yet, so its node is the tab bar's; give it its own when it owns session state.
    public var introspectionNode: any IntrospectionNode { tabs.introspectionNode }
}
