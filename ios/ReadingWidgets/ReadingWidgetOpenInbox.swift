import Foundation

/// The initial consume is the Dart-ready handshake. A warm delivery claims its
/// request before invoking Dart, so an overlapping consume cannot open it twice.
final class ReadingWidgetOpenInbox {
  typealias Delivery = (String, @escaping (Bool) -> Void) -> Void
  static let shared = ReadingWidgetOpenInbox()
  private let scheme: () -> String?
  private var pending: String?
  private var ready = false
  private var ticket = 0
  var deliver: Delivery?

  init(scheme: @escaping () -> String? = {
    Bundle.main.object(forInfoDictionaryKey: "WenkuWidgetScheme") as? String
  }) { self.scheme = scheme }

  @discardableResult func offer(_ url: URL, notify: Bool = true) -> Bool {
    guard let expected = scheme(), url.scheme == expected, url.host == "reading" else { return false }
    let destination = String(url.path.dropFirst())
    guard ["statistics", "moments", "continue", "excerpts"].contains(destination) else { return false }
    ticket += 1
    let offeredTicket = ticket
    pending = destination
    guard notify, ready, let deliver else { return true }
    pending = nil
    deliver(destination) { [weak self] accepted in
      guard let self, !accepted, self.ticket == offeredTicket else { return }
      self.pending = destination
      self.ready = false
    }
    return true
  }

  func consume() -> String? {
    ready = true
    let destination = pending
    pending = nil
    return destination
  }
}
