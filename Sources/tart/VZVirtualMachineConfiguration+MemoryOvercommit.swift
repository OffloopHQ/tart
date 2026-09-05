import Foundation
import Virtualization

enum MemoryOvercommitError: Error, CustomStringConvertible {
  case unavailable
  case rejected

  var description: String {
    switch self {
    case .unavailable:
      return "the host Virtualization.framework does not expose memory overcommitment"
    case .rejected:
      return "Virtualization.framework did not retain the memory overcommitment setting"
    }
  }
}

extension VZVirtualMachineConfiguration {
  private static let memoryOvercommitmentGetter = NSSelectorFromString("_memoryOvercommitmentAllowed")
  private static let memoryOvercommitmentSetter = NSSelectorFromString("_setMemoryOvercommitmentAllowed:")
  private static let pressureTerminationGetter = NSSelectorFromString("_terminationUnderMemoryPressureEnabled")
  private static let pressureTerminationSetter = NSSelectorFromString("_setTerminationUnderMemoryPressureEnabled:")
  private static let maximumOvercommittedMemorySizeGetter = NSSelectorFromString("_maximumAllowedOvercommittedMemorySize")

  static var supportsMemoryOvercommitment: Bool {
    instancesRespond(to: memoryOvercommitmentGetter)
      && instancesRespond(to: memoryOvercommitmentSetter)
      && instancesRespond(to: pressureTerminationGetter)
      && instancesRespond(to: pressureTerminationSetter)
      && responds(to: maximumOvercommittedMemorySizeGetter)
  }

  static var maximumAllowedOvercommittedMemorySize: UInt64? {
    guard supportsMemoryOvercommitment,
          let implementation = method(for: maximumOvercommittedMemorySizeGetter) else {
      return nil
    }

    typealias Getter = @convention(c) (AnyObject, Selector) -> UInt64
    return unsafeBitCast(implementation, to: Getter.self)(self, maximumOvercommittedMemorySizeGetter)
  }

  var isMemoryOvercommitmentAllowed: Bool? {
    guard Self.supportsMemoryOvercommitment,
          let implementation = method(for: Self.memoryOvercommitmentGetter) else {
      return nil
    }

    typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(implementation, to: Getter.self)(self, Self.memoryOvercommitmentGetter)
  }

  var isTerminationUnderMemoryPressureEnabled: Bool? {
    guard Self.supportsMemoryOvercommitment,
          let implementation = method(for: Self.pressureTerminationGetter) else {
      return nil
    }

    typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
    return unsafeBitCast(implementation, to: Getter.self)(self, Self.pressureTerminationGetter)
  }

  func allowMemoryOvercommitment() throws {
    guard Self.supportsMemoryOvercommitment,
          let overcommitSetter = method(for: Self.memoryOvercommitmentSetter),
          let terminationSetter = method(for: Self.pressureTerminationSetter) else {
      throw MemoryOvercommitError.unavailable
    }

    typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
    unsafeBitCast(terminationSetter, to: Setter.self)(self, Self.pressureTerminationSetter, true)
    unsafeBitCast(overcommitSetter, to: Setter.self)(self, Self.memoryOvercommitmentSetter, true)

    guard isMemoryOvercommitmentAllowed == true,
          isTerminationUnderMemoryPressureEnabled == true else {
      throw MemoryOvercommitError.rejected
    }
  }
}
