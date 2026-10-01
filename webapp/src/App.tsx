import { Route, Routes } from 'react-router-dom'
import { ConnectWalletGate } from './components/ConnectWalletGate'
import { GlobalActivityWatcher } from './components/GlobalActivityWatcher'
import { Layout } from './components/Layout'
import { ActivityPage } from './pages/ActivityPage'
import { BattlePage } from './pages/BattlePage'
import { BreedingLabPage } from './pages/BreedingLabPage'
import { CollectionPage } from './pages/CollectionPage'
import { FarmPage } from './pages/FarmPage'
import { InventoryPage } from './pages/InventoryPage'
import { LeaderboardPage } from './pages/LeaderboardPage'
import { MarketplacePage } from './pages/MarketplacePage'
import { TasksPage } from './pages/TasksPage'

export function App() {
  return (
    <ConnectWalletGate>
      {(wallet) => (
        <Layout wallet={wallet}>
          <GlobalActivityWatcher wallet={wallet} />
          <Routes>
            <Route path="/" element={<TasksPage wallet={wallet} />} />
            <Route path="/farm" element={<FarmPage wallet={wallet} />} />
            <Route path="/breeding" element={<BreedingLabPage wallet={wallet} />} />
            <Route path="/battle" element={<BattlePage wallet={wallet} />} />
            <Route path="/marketplace" element={<MarketplacePage wallet={wallet} />} />
            <Route path="/inventory" element={<InventoryPage wallet={wallet} />} />
            <Route path="/collection" element={<CollectionPage wallet={wallet} />} />
            <Route path="/leaderboard" element={<LeaderboardPage wallet={wallet} />} />
            <Route path="/activity" element={<ActivityPage wallet={wallet} />} />
          </Routes>
        </Layout>
      )}
    </ConnectWalletGate>
  )
}
