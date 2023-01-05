<script setup>
import { useWalletStore } from '@/stores/wallets'
import WalletStats from '@/components/WalletStats.vue'
import { ref } from 'vue'

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
    key: 'm',
    tab: 'Master'
  }
]

const tabChange = key => {
  useWalletStore().stopPolling(activeKey.value)
  useWalletStore().getWalletStats(key)
  activeKey.value = key
}
</script>

<template lang="pug">
.h-full.flex.flex-col
  a-card.shadow-md.rounded(
    title='Wallets',
    :tab-list='tabList',
    :active-tab-key='activeKey',
    @tabChange='key => tabChange(key)',
    :headStyle={ height: '6.1rem' }
  )
    WalletStats(:wallet='activeKey')
</template>
