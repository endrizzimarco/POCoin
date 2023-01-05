<script setup>
import Header from '@/components/layout/PageHeader.vue'
import NodeView from '@/components/layout/NodeView.vue'
import BlockchainView from '@/components/layout/BlockchainView.vue'
import WalletView from '@/components/layout/WalletView.vue'
</script>

<template lang="pug">
a-layout-header.flex.px-4.h-12.sticky.top-0.z-50
  Header
a-layout
  a-layout-content.p-5
    a-row
      a-col(:span='8')
        WalletView
      a-col(:span='8')
        BlockchainView
      a-col(:span='8')
        NodeView
</template>
