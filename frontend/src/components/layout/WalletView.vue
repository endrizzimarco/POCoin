<script setup>
import WalletStats from '@/components/WalletStats.vue'
import { useWalletStore } from '@/stores/wallets'
import { ref, onMounted } from 'vue'

const store = useWalletStore()
const activeKey = ref('w1')
const tabList = [
  {
    key: 'w1',
    tab: 'Alice'
  },
  {
    key: 'w2',
    tab: 'Bob'
  },
  {
    key: 'w3',
    tab: 'Charlie'
  },
  {
    key: 'w4',
    tab: 'Marco'
  },
  {
    key: 'w5',
    tab: 'Georgi'
  }
]

const tabChange = key => {
  store.stopPolling(activeKey.value)
  store.pollWallet(key)
  activeKey.value = key
}

onMounted(() => {
  store.initWalletsState()
  store.pollWallet(activeKey.value)
})
</script>

<template lang="pug">
a-card.shadow-md.rounded(
  :tab-list='tabList',
  :active-tab-key='activeKey',
  @tabChange='key => tabChange(key)',
  style='height: 90vh'
)
  WalletStats(:wallet='activeKey')
</template>
