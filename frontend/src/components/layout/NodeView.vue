<script setup>
import NodeStats from '@/components/NodeStats.vue'
import { useNodeStore } from '@/stores/nodes'
import { ref, onMounted } from 'vue'

const store = useNodeStore()
const activeKey = ref('n1')
const tabList = [
  {
    key: 'n1',
    tab: 'Node 1'
  },
  {
    key: 'n2',
    tab: 'Node 2'
  },
  {
    key: 'n3',
    tab: 'Node 3'
  },
  {
    key: 'n4',
    tab: 'Node 4'
  },
  {
    key: 'n5',
    tab: 'Node 5'
  }
]

const tabChange = key => {
  store.stopPolling(activeKey.value)
  store.pollNode(key)
  activeKey.value = key
}

onMounted(() => {
  store.initNodesState()
  store.pollNode(activeKey.value)
})
</script>

<template lang="pug">
.h-full.flex.flex-col
  a-card.shadow-md.rounded(
    title='Nodes',
    :tab-list='tabList',
    :active-tab-key='activeKey',
    @tabChange='key => tabChange(key)',
    :headStyle={ height: '6.1rem' }
  )
    NodeStats(:node='activeKey')
</template>
