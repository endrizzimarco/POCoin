<script setup>
import { ref } from 'vue'
import WalletStats from '@/components/WalletStats.vue'

const activeKey = ref('w1')
const stopPolling = () => this.$emit('stopPolling', activeKey)

const tabList = [
  {
    key: 'm',
    tab: 'Master'
  },
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
  }
]
</script>

<template lang="pug">
.h-full.flex.flex-col
  a-card.shadow-md.rounded(
    title='Wallets',
    :tab-list='tabList',
    :active-tab-key='activeKey',
    @tabChange='key => (activeKey = key)',
    headStyle='height: 6.1rem;'
  )
    WalletStats(:wallet='activeKey')
</template>
