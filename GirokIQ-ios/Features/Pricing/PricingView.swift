import SwiftUI

enum PricingEntryPoint: Equatable {
    case settings
    case storage

    var badgeTitle: String {
        switch self {
        case .settings:
            return "Subscription"
        case .storage:
            return "Storage"
        }
    }
}

enum PricingBillingCycle: String, CaseIterable, Identifiable {
    case monthly
    case annual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly:
            return "Monthly"
        case .annual:
            return "Annual"
        }
    }
}

struct PricingView: View {
    let entryPoint: PricingEntryPoint

    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var billingCycle: PricingBillingCycle = .annual

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var proPriceText: String {
        switch billingCycle {
        case .monthly:
            return purchaseManager.displayPrice(for: .monthly, fallback: "$4.99")
        case .annual:
            return purchaseManager.displayPrice(for: .annual, fallback: "$39.99")
        }
    }

    private var proPriceSuffix: String {
        switch billingCycle {
        case .monthly:
            return "/mo"
        case .annual:
            return "/yr"
        }
    }

    private var proBillingDetail: String {
        switch billingCycle {
        case .monthly:
            return "Billed monthly"
        case .annual:
            return "About $3.33/month billed yearly"
        }
    }

    private var proSavingsText: String {
        switch billingCycle {
        case .monthly:
            return "Flexible month to month"
        case .annual:
            return "Save 33% with annual"
        }
    }

    private var primaryCTA: String {
        if isCurrentSelectedProPlan {
            return "Current Plan"
        }

        switch billingCycle {
        case .monthly:
            return purchaseManager.hasProAccess ? "Switch to Monthly" : "Unlock Pro Monthly"
        case .annual:
            return purchaseManager.hasProAccess ? "Switch to Annual" : "Unlock Pro Annual"
        }
    }

    private var selectedPurchaseCycle: PurchaseManager.PurchaseCycle {
        switch billingCycle {
        case .monthly:
            return .monthly
        case .annual:
            return .annual
        }
    }

    private var isCurrentSelectedProPlan: Bool {
        purchaseManager.hasProAccess && purchaseManager.activeProductID == selectedPurchaseCycle.productID
    }

    private var isPurchasingCurrentSelection: Bool {
        purchaseManager.purchaseInProgressProductID == selectedPurchaseCycle.productID
    }

    var body: some View {
        ZStack {
            Color.gBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    Group {
                        if isWideLayout {
                            HStack(alignment: .top, spacing: GSpacing.xl) {
                                valuePane
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                pricingPane
                                    .frame(maxWidth: 460, alignment: .top)
                            }
                        } else {
                            VStack(spacing: GSpacing.xl) {
                                valuePane
                                pricingPane
                            }
                        }
                    }
                    .padding(.horizontal, isWideLayout ? GSpacing.xxxl : GSpacing.lg)
                    .padding(.vertical, GSpacing.xl)
                    .frame(maxWidth: 1280, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .task {
            await purchaseManager.refreshProducts()
            await purchaseManager.refreshEntitlementsAndSync()
        }
    }

    private var topBar: some View {
        HStack(spacing: GSpacing.md) {
            HStack(spacing: GSpacing.sm) {
                Image("SidebarLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("GirokIQ")
                        .font(.gSubheadline.weight(.semibold))
                        .foregroundColor(.gTextPrimary)
                    Text("Pro")
                        .font(.gCaption.weight(.medium))
                        .foregroundColor(.gTextSecondary)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.gIconMedium.weight(.semibold))
                    .foregroundColor(.gTextSecondary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.gElevated.opacity(0.82))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close pricing")
        }
        .padding(.horizontal, isWideLayout ? GSpacing.xxxl : GSpacing.lg)
        .padding(.vertical, GSpacing.md)
        .background(
            Color.gBackground
                .overlay(alignment: .bottom) {
                    Divider()
                        .overlay(Color.gBorder.opacity(0.35))
                }
        )
    }

    private var valuePane: some View {
        VStack(alignment: .leading, spacing: GSpacing.xl) {
            VStack(alignment: .leading, spacing: GSpacing.md) {
                Text(entryPoint.badgeTitle.uppercased())
                    .font(.gCaption.weight(.semibold))
                    .kerning(0.8)
                    .foregroundColor(.gPrimary)
                    .padding(.horizontal, GSpacing.sm)
                    .padding(.vertical, GSpacing.xs)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.gPrimaryMuted)
                    )

                Text("Unlock unlimited notebooks, more cloud space, and smarter AI.")
                    .font(.custom("InstrumentSerif-Regular", size: isWideLayout ? 46 : 34))
                    .foregroundColor(.gTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(entryPoint == .storage
                     ? "Manage your storage plan, sync space, and AI access."
                     : "Choose the plan that fits your notebooks, sync, and AI usage.")
                    .font(.gCallout)
                    .foregroundColor(.gTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            featureGrid
        }
    }

    private var featureGrid: some View {
        Group {
            if isWideLayout {
                HStack(alignment: .top, spacing: GSpacing.md) {
                    featureCard(
                        title: "Notebook freedom",
                        subtitle: "Move past the starter cap and keep bigger projects in one place.",
                        rows: [
                            ("Unlimited notebooks", "book.closed"),
                            ("Full canvas and export flow", "square.and.arrow.up"),
                            ("Priority early feature access", "sparkles")
                        ]
                    )

                    featureCard(
                        title: "Cloud and AI",
                        subtitle: "Give heavy notebooks more room to sync, back up, and reason.",
                        rows: [
                            ("10 GB cloud sync and backup", "icloud"),
                            ("Higher AI limits", "brain.head.profile"),
                            ("Most capable AI model access", "bolt")
                        ]
                    )
                }
            } else {
                VStack(spacing: GSpacing.md) {
                    featureCard(
                        title: "Notebook freedom",
                        subtitle: "Move past the starter cap and keep bigger projects in one place.",
                        rows: [
                            ("Unlimited notebooks", "book.closed"),
                            ("Full canvas and export flow", "square.and.arrow.up"),
                            ("Priority early feature access", "sparkles")
                        ]
                    )

                    featureCard(
                        title: "Cloud and AI",
                        subtitle: "Give heavy notebooks more room to sync, back up, and reason.",
                        rows: [
                            ("10 GB cloud sync and backup", "icloud"),
                            ("Higher AI limits", "brain.head.profile"),
                            ("Most capable AI model access", "bolt")
                        ]
                    )
                }
            }
        }
    }

    private var pricingPane: some View {
        VStack(alignment: .leading, spacing: GSpacing.lg) {
            VStack(alignment: .leading, spacing: GSpacing.md) {
                Text("Choose your plan")
                    .font(.gTitle2)
                    .foregroundColor(.gTextPrimary)

                billingCyclePicker
            }

            if authViewModel.subscriptionTier == .pro {
                statusBanner(
                    title: "GirokIQ Pro is active",
                    message: purchaseManager.activeProductID == PurchaseManager.annualProductID
                        ? "Your annual Pro entitlement is currently active on this account."
                        : "Your monthly Pro entitlement is currently active on this account.",
                    accent: .gSuccess
                )
            }

            if authViewModel.subscriptionTier == .pro {
                Button {
                    Task {
                        await purchaseManager.openManageSubscriptions()
                    }
                } label: {
                    HStack {
                        Text("Manage Subscription")
                            .font(.gSubheadline.weight(.semibold))
                            .foregroundColor(.gPrimary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.gFootnote.weight(.bold))
                            .foregroundColor(.gPrimary)
                    }
                    .padding(GSpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                            .fill(Color.gPrimaryMuted.opacity(0.7))
                    )
                }
                .buttonStyle(.plain)
            }

            if let info = purchaseManager.purchaseInfoMessage, !info.isEmpty {
                statusBanner(title: "App Store", message: info, accent: .gPrimary)
            }

            if let error = purchaseManager.purchaseErrorMessage, !error.isEmpty {
                statusBanner(title: "Purchase issue", message: error, accent: .gDestructive)
            }

            freePlanCard
            proPlanCard

            GButton(
                title: primaryCTA,
                style: .primary,
                isLoading: isPurchasingCurrentSelection || purchaseManager.isRefreshingEntitlements,
                isDisabled: isCurrentSelectedProPlan || purchaseManager.isLoadingProducts
            ) {
                Task {
                    _ = await purchaseManager.purchase(cycle: selectedPurchaseCycle)
                }
            }
            .buttonStyle(GScaleButtonStyle())

            VStack(alignment: .leading, spacing: GSpacing.xs) {
                Text("Subscriptions will be managed through the App Store.")
                    .font(.gCaption.weight(.semibold))
                    .foregroundColor(.gTextPrimary)

                Text("Cancel anytime. The annual plan shows both the billed yearly amount and the monthly equivalent so the charge stays clear.")
                    .font(.gCaption)
                    .foregroundColor(.gTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: GSpacing.md) {
                Button("Restore Purchases") {
                    Task {
                        await purchaseManager.restorePurchases()
                    }
                }
                .font(.gCaption.weight(.semibold))
                .foregroundColor(.gPrimary)
                .disabled(purchaseManager.isRefreshingEntitlements)

                Link("Terms", destination: URL(string: "https://girokiq.app/terms")!)
                    .font(.gCaption.weight(.semibold))
                    .foregroundColor(.gPrimary)

                Link("Privacy", destination: URL(string: "https://girokiq.app/privacy")!)
                    .font(.gCaption.weight(.semibold))
                    .foregroundColor(.gPrimary)
            }
        }
        .padding(GSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)
                .fill(Color.gSurface.opacity(0.96))
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)
                .stroke(Color.gBorder.opacity(0.75), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
    }

    private var billingCyclePicker: some View {
        HStack(spacing: GSpacing.xs) {
            ForEach(PricingBillingCycle.allCases) { cycle in
                Button {
                    withAnimation(GAnimation.motionSafe(.spring(response: 0.28, dampingFraction: 0.86))) {
                        billingCycle = cycle
                    }
                } label: {
                    HStack(spacing: GSpacing.xs) {
                        Text(cycle.title)
                            .font(.gSubheadline.weight(.semibold))

                        if cycle == .annual {
                            Text("Save 33%")
                                .font(.gCaption.weight(.semibold))
                                .foregroundColor(billingCycle == .annual ? .black.opacity(0.72) : .gPrimary)
                                .padding(.horizontal, GSpacing.xs)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(billingCycle == .annual ? Color.white.opacity(0.46) : Color.gPrimaryMuted)
                                )
                        }
                    }
                    .foregroundColor(billingCycle == cycle ? .black.opacity(0.75) : .gTextSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                            .fill(billingCycle == cycle ? Color.gPrimary : Color.gElevated.opacity(0.82))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var freePlanCard: some View {
        planCard(
            title: "Student",
            price: "$0",
            priceSuffix: "forever",
            billingDetail: "A calm place to start taking notes on iPad.",
            accent: false,
            badge: nil,
            features: [
                "3 notebooks",
                "1 GB cloud sync and backup",
                "Faster AI model with 10 daily requests",
                "Export to PDF and image"
            ]
        )
    }

    private var proPlanCard: some View {
        planCard(
            title: "Pro",
            price: proPriceText,
            priceSuffix: proPriceSuffix,
            billingDetail: proBillingDetail,
            accent: true,
            badge: proSavingsText,
            features: [
                "Everything in Student",
                "Unlimited notebooks",
                "10 GB cloud sync and backup",
                "Most capable AI models with higher limits",
                "Priority early access and roadmap voting"
            ]
        )
    }

    private func statusBanner(title: String, message: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: GSpacing.sm) {
            Circle()
                .fill(accent)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.gCaption.weight(.semibold))
                    .foregroundColor(.gTextPrimary)

                Text(message)
                    .font(.gCaption)
                    .foregroundColor(.gTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(GSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: GRadius.lg, style: .continuous)
                .fill(Color.gElevated.opacity(0.62))
        )
    }

    private func featureCard(title: String, subtitle: String, rows: [(String, String)]) -> some View {
        GCard(cornerRadius: GRadius.xl) {
            VStack(alignment: .leading, spacing: GSpacing.md) {
                VStack(alignment: .leading, spacing: GSpacing.xs) {
                    Text(title)
                        .font(.gHeadline)
                        .foregroundColor(.gTextPrimary)

                    Text(subtitle)
                        .font(.gSubheadline)
                        .foregroundColor(.gTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: GSpacing.sm) {
                    ForEach(rows, id: \.0) { row in
                        HStack(alignment: .top, spacing: GSpacing.sm) {
                            Image(systemName: row.1)
                                .font(.gFootnote.weight(.semibold))
                                .foregroundColor(.gPrimary)
                                .frame(width: 18, height: 18)
                            Text(row.0)
                                .font(.gSubheadline)
                                .foregroundColor(.gTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            .padding(GSpacing.lg)
        }
    }

    private func planCard(
        title: String,
        price: String,
        priceSuffix: String,
        billingDetail: String,
        accent: Bool,
        badge: String?,
        features: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: GSpacing.md) {
            HStack(alignment: .top, spacing: GSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.gTitle3)
                        .foregroundColor(.gTextPrimary)

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(price)
                            .font(.custom("InstrumentSerif-Regular", size: accent ? 46 : 36))
                            .foregroundColor(.gTextPrimary)

                        Text(priceSuffix)
                            .font(.gBody)
                            .foregroundColor(.gTextSecondary)
                    }
                }

                Spacer(minLength: 0)

                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.gCaption.weight(.semibold))
                        .foregroundColor(accent ? .black.opacity(0.75) : .gPrimary)
                        .padding(.horizontal, GSpacing.sm)
                        .padding(.vertical, GSpacing.xs)
                        .background(
                            Capsule(style: .continuous)
                                .fill(accent ? Color.gPrimary.opacity(0.26) : Color.gPrimaryMuted)
                        )
                }
            }

            Text(billingDetail)
                .font(.gSubheadline)
                .foregroundColor(.gTextSecondary)

            Divider()
                .overlay(Color.gBorder.opacity(0.55))

            VStack(alignment: .leading, spacing: GSpacing.sm) {
                ForEach(features, id: \.self) { feature in
                    HStack(alignment: .top, spacing: GSpacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.gFootnote)
                            .foregroundColor(accent ? .gPrimary : .gTextTertiary)
                            .padding(.top, 2)

                        Text(feature)
                            .font(.gSubheadline)
                            .foregroundColor(.gTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(GSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)
                .fill(accent ? Color.gPrimaryMuted.opacity(0.82) : Color.gElevated.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: GRadius.xl, style: .continuous)
                .stroke(accent ? Color.gPrimary.opacity(0.55) : Color.gBorder.opacity(0.75), lineWidth: accent ? 1.4 : 0.8)
        )
    }
}
